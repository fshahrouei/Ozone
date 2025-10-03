<?php

namespace App\Http\Controllers\API\V1\Frontend\AirQualities;

use Illuminate\Http\Request;

/**
 * ForecastTime
 *
 * Lightweight readiness probe for the short-term forecast pipeline.
 * It checks:
 *  - TEMPO product recency (NO2 or O3 total) against a backoff window
 *  - Availability of recent station observations (NO2/O3) within a backoff window
 *
 * Output is a compact JSON telling the client whether forecast time steps
 * (t = 0..+12h) are "ready" given upstream data freshness/coverage.
 *
 * NOTE: Business logic, data paths, and thresholds are intentionally left intact.
 */
class ForecastTime
{
    /** Max age (hours) for TEMPO inputs to still be considered fresh. */
    private const TEMPO_BACKOFF_H = 18;

    /** Max age (hours) for station observations to be considered usable. */
    private const STATION_BACKOFF_H = 72;

    /** Minimum station rows required for NO2 readiness. */
    private const READY_MIN_NO2 = 60;

    /** Minimum station rows required for O3 readiness. */
    private const READY_MIN_O3  = 40;

    /**
     * Build readiness JSON for a product.
     *
     * Query params:
     *   - product: 'no2' | 'o3' (default: 'no2')
     *
     * Response (200):
     * {
     *   "succeed": true,
     *   "status": 200,
     *   "product": "no2",
     *   "latest": {
     *     "tempo_ok": true,
     *     "tempo_age_h": 3.25,
     *     "stations_count": 97
     *   },
     *   "times": [
     *     {"t":"+0h","ready":true}, ... {"t":"+12h","ready":true}
     *   ],
     *   "message": "ok" | "partial: station data insufficient/outdated — forecast output may be lower quality."
     * }
     */
    public function build(Request $req)
    {
        $product = strtolower((string)$req->query('product', 'no2'));
        if (!in_array($product, ['no2','o3'], true)) {
            return response()->json(
                ['succeed'=>false,'status'=>400,'message'=>"Invalid product. Allowed: no2|o3"],
                400
            );
        }

        // Map API product to TEMPO base name
        $tempoBase = ($product==='no2') ? 'no2' : 'o3tot';

        // Check TEMPO recency; captures best (freshest) file age in $ageH
        $tempoOk = $this->tempoRecentEnough($tempoBase, self::TEMPO_BACKOFF_H, $ageH);

        // Load the most recent non-empty, valid station rows within backoff
        $rows = $this->stationsRows($product, self::STATION_BACKOFF_H);
        $count = count($rows);

        // Product-specific minimum coverage threshold
        $minCount = ($product==='no2') ? self::READY_MIN_NO2 : self::READY_MIN_O3;

        // Readiness means both: TEMPO fresh enough AND enough station coverage
        $ready = $tempoOk && ($count >= $minCount);

        // Expose a simple 0..+12h horizon, all tied to the same readiness flag
        $times = [];
        for ($k=0;$k<=12;$k++){
            $times[] = [ 't'=>"+{$k}h", 'ready'=>$ready ];
        }

        return response()->json([
            'succeed'=>true,
            'status'=>200,
            'product'=>$product,
            'latest'=>[
                'tempo_ok' => $tempoOk,
                'tempo_age_h' => $ageH,
                'stations_count' => $count,
            ],
            'times'=>$times,
            'message'=>$ready
                ? 'ok'
                : 'partial: station data insufficient/outdated — forecast output may be lower quality.'
        ], 200, ['Cache-Control'=>'public, max-age=120']);
    }

    /**
     * Check if the latest TEMPO artifact for a product is recent enough.
     *
     * @param string      $product   'no2' | 'o3tot'
     * @param int         $backoffH  Max allowed age in hours
     * @param float|null &$ageHours  OUT: best (lowest) age in hours for the winner file
     * @return bool                  True if a file within backoff window exists
     */
    private function tempoRecentEnough(string $product, int $backoffH, ?float &$ageHours): bool {
        $idxPath = storage_path("app/tempo/{$product}/json/index.json");
        $ageHours = null;

        if (!is_file($idxPath)) return false;

        $idx = json_decode(@file_get_contents($idxPath), true);
        if (!is_array($idx) || empty($idx)) return false;

        $bestEnd = 0; $bestAge=null; $now = time();

        foreach ($idx as $meta){
            // Prefer 'subset_time[1]' (end) then fallback to 'saved'
            $t1 = (string)(($meta['subset_time'] ?? [null,null])[1] ?? ($meta['t1'] ?? ''));
            $end = strtotime($t1) ?: strtotime((string)($meta['saved'] ?? ''));
            if (!$end) continue;

            $age = ($now - $end)/3600.0;

            // Keep the freshest file that is within the backoff window
            if ($age <= $backoffH && $end > $bestEnd) {
                $bestEnd = $end;
                $bestAge = $age;
            }
        }

        if ($bestEnd===0) return false;

        $ageHours = $bestAge;
        return true;
    }

    /**
     * Return the most recent non-empty, valid station rows within a backoff window.
     *
     * Walks backward hour-by-hour (≤ backoffH) and returns the first hour that:
     *  - Exists on disk
     *  - Decodes to a non-empty array
     *  - Contains rows with valid numeric value/lat/lon and matching parameter
     *
     * @param string $product  'no2' | 'o3'
     * @param int    $backoffH Max hours to look back
     * @return array           Valid station rows for counting/coverage
     */
    private function stationsRows(string $product, int $backoffH): array {
        $param = ($product==='no2') ? 'no2' : 'o3';
        $now = time();

        for ($age=0; $age<=$backoffH; $age++){
            $ts  = $now - $age*3600;
            $fn  = gmdate('Y-m-d\TH', $ts) . '.json';   // e.g. 2025-09-07T18.json
            $path = storage_path("app/stations/{$param}/json/hours/{$fn}");
            if (!is_file($path)) continue;

            $arr = json_decode(@file_get_contents($path), true);
            if (!is_array($arr) || count($arr)===0) continue;

            $valid=[];
            foreach ($arr as $r){
                if (($r['parameter'] ?? '') !== $param) continue;

                $v  = $r['value'] ?? null;
                $la = $r['lat'] ?? null;
                $lo = $r['lon'] ?? null;

                if (!is_numeric($v) || !is_numeric($la) || !is_numeric($lo)) continue;

                $valid[] = $r;
            }

            if (count($valid) > 0) return $valid;
        }

        return [];
    }
}
