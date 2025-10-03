<?php

namespace App\Http\Controllers\API\V1\Frontend;

use Illuminate\Support\Str;
use App\Http\Controllers\API\V1\Frontend\FrontendBaseController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

// Module services
use App\Http\Controllers\API\V1\Frontend\AirQualities\Tempo;
use App\Http\Controllers\API\V1\Frontend\AirQualities\Overlays;
use App\Http\Controllers\API\V1\Frontend\AirQualities\OverlaysTime;
use App\Http\Controllers\API\V1\Frontend\AirQualities\OverlaysLegend;
use App\Http\Controllers\API\V1\Frontend\AirQualities\Forecast;
use App\Http\Controllers\API\V1\Frontend\AirQualities\ForecastTime;
use App\Http\Controllers\API\V1\Frontend\AirQualities\OverlayGrids; // NEW
use App\Http\Controllers\API\V1\Frontend\AirQualities\ForecastGrids;
use App\Http\Controllers\API\V1\Frontend\AirQualities\PointAssess;
use App\Http\Controllers\API\V1\Frontend\AirQualities\Stations;
use App\Http\Controllers\API\V1\Frontend\AirQualities\AppStatus;


/**
 * AirQualitiesController
 * Routes:
 *  - get-tempo-data  → proxy to Tempo service
 *  - overlays        → render PNG overlays from gridded JSON
 *  - overlay-times   → timeline (frames) + latest
 *  - app-status      → general status + day/night at user location
 */
class AirQualitiesController extends FrontendBaseController
{
    /* ===================== Entry Points (Routes) ===================== */

    /** Proxy to Tempo service (keeps response shape from service) */
    public function getTempoData(Request $request)
    {
        $svc = new Tempo();
        // Be flexible if the service entrypoint was named differently
        if (method_exists($svc, 'build')) {
            $res = $svc->build($request);
        } else {
            return $this->j([
                'succeed' => false,
                'status'  => 500,
                'message' => 'Tempo service entrypoint not found.',
            ], 500);
        }

        $status = (int)($res['status'] ?? 200);
        return $this->j($res, $status);
    }

    /** Overlay PNG */
    public function overlays(Request $request)
    {
        $svc = new Overlays();
        return $svc->build($request);
    }

    public function overlayTimes(Request $request)
    {
        $svc = new overlaysTime();
        return $svc->build($request);
    }

    /** Legend (colors, ticks, labels) */
    public function legend(Request $request)
    {
        $svc = new OverlaysLegend();
        return $svc->build($request);
    }

    // for zoom > 8
    public function overlayGrids(Request $request)
    {
        $svc = new OverlayGrids();
        return $svc->build($request);
    }



    /** Forecast PNG/JSON */
    public function forecast(Request $request)
    {
        $svc = new Forecast();
        return $svc->build($request);
    }

    /** Forecast times list */
    public function forecastTimes(Request $request)
    {
        $svc = new ForecastTime();
        return $svc->build($request);
    }


    public function ForecastGrids(Request $request)
    {
        $svc = new ForecastGrids();
        return $svc->build($request);
    }

    public function PointAssess(Request $request)
    {
        $svc = new PointAssess();
        return $svc->build($request);
    }

    public function Stations(Request $request)
    {
        $svc = new Stations();
        return $svc->build($request);
    }

    /**
     * app-status
     * Optional query: product=(no2|hcho|o3tot|cldo4), lat, lon
     * Returns: latest frame meta, units, and is_day for the given coords
     */
    public function appStatus(Request $request)
    {
        $svc = new AppStatus();
        return $svc->build($request);
    }

    public function appStatusBK(Request $request)
    {
        $product = strtolower((string)$request->query('product', 'no2'));
        $allowed = ['no2', 'hcho', 'o3tot', 'cldo4'];
        if (!in_array($product, $allowed, true)) {
            $product = 'no2'; // fallback
        }

        $spec = $this->productSpec($product);

        // index.json
        $indexPath = storage_path("app/tempo/{$product}/json/index.json");
        if (!is_file($indexPath)) {
            return $this->j([
                'succeed' => false,
                'status'  => 404,
                'message' => "index.json for '{$product}' not found.",
                'product' => $product,
                'units'   => $spec['units'],
            ], 404);
        }
        $idx = $this->readJsonFileSafely($indexPath);
        if (!is_array($idx) || empty($idx)) {
            return $this->j([
                'succeed' => false,
                'status'  => 404,
                'message' => "index.json is empty/invalid.",
                'product' => $product,
                'units'   => $spec['units'],
            ], 404);
        }

        // latest frame
        $latest = null;
        $latestEpoch = null;
        foreach ($idx as $gid => $meta) {
            if (!is_array($meta)) continue;
            $t0 = isset($meta['t0']) ? (string)$meta['t0'] : (string)($meta['start'] ?? '');
            $t1 = isset($meta['t1']) ? (string)$meta['t1'] : (string)($meta['end'] ?? '');
            $e0 = $this->toEpoch($t0);
            $e1 = $this->toEpoch($t1);
            $e  = $e1 ?? $e0 ?? null;
            if ($e === null) continue;
            if ($latestEpoch === null || $e > $latestEpoch) {
                $latestEpoch = $e;
                $latest = [
                    'gid'   => (string)$gid,
                    'start' => $t0 ?: null,
                    'end'   => $t1 ?: null,
                ];
            }
        }

        // day/night (optional by lat/lon)
        $lat = $request->query('lat');
        $lon = $request->query('lon');
        $isDay = null;
        if (is_numeric($lat) && is_numeric($lon)) {
            $isDay = $this->isDayAt((float)$lat, (float)$lon, time());
        }

        // extras
        $now = time();
        $nowIso = gmdate('Y-m-d\TH:i:s\Z', $now);
        $ageMin = $latestEpoch !== null ? max(0, (int)floor(($now - $latestEpoch) / 60)) : null;
        $tempoLive = ($ageMin !== null && $ageMin <= 180);

        // ---- concise 3-part message ----
        // day=true  → "TEMPO • day • live|stale"
        // day=false → "TEMPO • night • live|stale"
        // day=null  → "TEMPO • n/a • live|stale"
        $phase = ($isDay === true) ? 'day' : (($isDay === false) ? 'night' : 'n/a');
        $fresh = $tempoLive ? 'live' : 'stale';
        $message = "TEMPO • {$phase} • {$fresh}";

        return $this->j([
            'succeed'    => true,
            'status'     => 200,
            'product'    => $product,
            'units'      => $spec['units'],
            'latest'     => $latest,
            'tempo_gid'  => $latest['gid'] ?? null,
            'now_utc'    => $nowIso,
            'age_min'    => $ageMin,
            'tempo_live' => $tempoLive,
            'is_day'     => $isDay,
            'message'    => $message,
        ], 200, [
            'Cache-Control' => 'public, max-age=120, s-maxage=120',
        ]);
    }




    /**
     * Cache headers for app-status; optional ?nocache=1 disables caching.
     */
    private function statusCacheHeaders(Request $request): array
    {
        $nocache = (string)$request->query('nocache', '0') === '1';
        if ($nocache) {
            return [
                'Cache-Control' => 'no-store, no-cache, must-revalidate, max-age=0',
                'Pragma'        => 'no-cache',
                'Expires'       => '0',
            ];
        }
        // Default aligned with your previous code (adjustable)
        return [
            'Cache-Control' => 'public, max-age=120, s-maxage=120',
        ];
    }


    /* ===================== Helpers ===================== */

    /** Unified JSON responder with optional extra headers */
    private function j($payload, int $status = 200, array $extraHeaders = [])
    {
        $headers = array_merge(
            ['Content-Type' => 'application/json; charset=utf-8'],
            $extraHeaders
        );
        return response()->json(
            $payload,
            $status,
            $headers,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
        );
    }

    /** Safe JSON file reader with shared lock */
    private function readJsonFileSafely(string $path)
    {
        $raw = null;
        for ($try = 0; $try < 2; $try++) {
            $fh = @fopen($path, 'rb');
            if ($fh) {
                @flock($fh, LOCK_SH);
                $raw = @stream_get_contents($fh);
                @flock($fh, LOCK_UN);
                @fclose($fh);
            }
            if (is_string($raw) && $raw !== '') break;
            usleep(50000);
        }
        $js = json_decode((string)$raw, true);
        return is_array($js) ? $js : null;
    }

    /** Minimal product spec for units/palette (aligned with Overlays/OverlaysTime) */
    private function productSpec(string $product): array
    {
        switch ($product) {
            case 'no2':
                return [
                    'units'     => 'molec/cm²',
                    'cap'       => 1.2e16,
                    'qLow'      => 0.10,
                    'qHigh'     => 0.98,
                    'palette'   => 'viridis',
                    'allowZero' => false,
                ];
            case 'hcho':
                return [
                    'units'     => 'molec/cm²',
                    'cap'       => 1.0e16,
                    'qLow'      => 0.10,
                    'qHigh'     => 0.98,
                    'palette'   => 'viridis',
                    'allowZero' => false,
                ];
            case 'o3tot':
                return [
                    'units'     => 'DU',
                    'cap'       => 700.0,
                    'qLow'      => 0.05,
                    'qHigh'     => 0.98,
                    'palette'   => 'viridis',
                    'allowZero' => false,
                ];
            case 'cldo4':
                return [
                    'units'     => 'fraction (0..1)',
                    'cap'       => 1.0,
                    'qLow'      => 0.00,
                    'qHigh'     => 0.98,
                    'palette'   => 'gray',
                    'allowZero' => true,
                ];
        }
        return [
            'units'     => '',
            'cap'       => 1.0,
            'qLow'      => 0.10,
            'qHigh'     => 0.98,
            'palette'   => 'viridis',
            'allowZero' => false,
        ];
    }

    private function toEpoch(?string $iso): ?int
    {
        if (!$iso) return null;
        $t = strtotime($iso);
        return $t !== false ? $t : null;
    }

    /**
     * Day/Night detection for lat/lon.
     * - Prefer date_sun_info; fallback to a crude lon-based timezone offset.
     */
    private function isDayAt(float $lat, float $lon, ?int $nowUtc = null): bool
    {
        $nowUtc = $nowUtc ?? time();

        // Noon of the same day (for stable sunrise/sunset calculation)
        $date = getdate($nowUtc);
        $tsNoon = gmmktime(12, 0, 0, $date['mon'], $date['mday'], $date['year']);

        if (function_exists('date_sun_info')) {
            $info = @date_sun_info($tsNoon, $lat, $lon);
            if (is_array($info)) {
                $rise = $info['sunrise'] ?? null;
                $set  = $info['sunset']  ?? null;
                if (is_int($rise) && is_int($set) && $rise > 0 && $set > 0) {
                    return ($nowUtc >= $rise) && ($nowUtc <= $set);
                }
            }
        }

        // Fallback: approximate local hour by longitude
        $offsetSec = (int) round(($lon / 15.0) * 3600);
        $local = $nowUtc + $offsetSec;
        $h = (int) gmdate('G', $local);
        return ($h >= 7 && $h < 19);
    }

    /** Kept for compatibility – this controller has no special rules */
    public function getRules($params)
    {
        return [];
    }
}
