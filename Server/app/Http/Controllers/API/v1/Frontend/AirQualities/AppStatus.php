<?php

namespace App\Http\Controllers\API\V1\Frontend\AirQualities;

use Illuminate\Http\Request;

class AppStatus
{
    /* ===================== Config ===================== */
    // Supported atmospheric products
    private const PRODUCTS = ['no2', 'hcho', 'o3tot', 'cldo4'];

    // Minimum and maximum allowed zoom levels
    private const Z_MIN = 3;
    private const Z_MAX = 12;

    // Maximum forecast horizon (in hours)
    private const FORECAST_HOURS_MAX = 12;

    // Maximum age window (minutes) for TEMPO live observations
    private const TEMPO_LIVE_WINDOW_MIN = 180;

    // Path to stations/sensors geojson file
    private const STATIONS_GEOM_PATH = 'storage/app/stations/_common/sensors.geojson';

    /* ===================== Public ===================== */
    public function build(Request $request)
    {
        $nowTs  = time();
        $nowIso = $this->isoUtc($nowTs);

        // -------- inputs --------
        // product
        $product = strtolower((string)$request->query('product', 'no2'));
        if (!in_array($product, self::PRODUCTS, true)) {
            $product = 'no2';
        }
        $spec = $this->productSpec($product);

        // zoom level
        $z = (int)($request->query('z', 5));
        if ($z < self::Z_MIN) $z = self::Z_MIN;
        if ($z > self::Z_MAX) $z = self::Z_MAX;

        // coordinates
        $lat = $request->query('lat');
        $lon = $request->query('lon');

        // time identifiers
        $gid   = $request->query('gid');      // past (real observation by gid)
        $tRaw  = $request->query('t', null);  // forecast or now
        $tNorm = $this->normalizeT($tRaw);

        // -------- latest TEMPO (real observation) --------
        $tempoLatestInfo = $this->readTempoLatest($product);
        $latest     = $tempoLatestInfo['latest'];   // ['gid','start','end'] or null
        $tempoGid   = $latest['gid'] ?? null;

        // Age of latest TEMPO observation (difference between now and latest.start/end)
        $tempoAgeMin = $tempoLatestInfo['age_min']; // may be null
        $tempoLive   = ($tempoAgeMin !== null && $tempoAgeMin <= self::TEMPO_LIVE_WINDOW_MIN);

        // -------- day/night flag --------
        $isDay = null;
        if (is_numeric($lat) && is_numeric($lon)) {
            $isDay = $this->isDayAt((float)$lat, (float)$lon, $nowTs);
        }

        // -------- mode selection & reference frame --------
        $mode = null;
        $frameIso = null;     // reference frame for UI (past/now/forecast)
        $echoT = null;        // normalized t
        $echoGid = null;      // normalized gid

        if (is_string($gid) && $gid !== '') {
            // ==== PAST (real by gid) ====
            $mode = 'real';
            $echoGid = (string)$gid;
            $frameIso = $this->lookupGidFrameIso($product, $echoGid); // usually equals end
            if ($frameIso === null) {
                return response()->json([
                    'succeed' => false,
                    'status'  => 404,
                    'message' => "gid '{$echoGid}' not found for product '{$product}'.",
                ], 404, $this->stdHeaders());
            }
            $echoT = null;
        } elseif ($tNorm !== null) {
            // ==== FORECAST/NOW (by t) ====
            $mode = 'forecast';
            $echoT = $tNorm ?? 'now';
            $echoGid = null;

            // Base hour (rounded down to the current hour)
            $baseHourTs = (int)floor($nowTs / 3600) * 3600;
            if ($echoT === 'now') {
                // Current/past hour start
                $frameIso = $this->isoUtc($baseHourTs);
            } else {
                // +H (clamped to FORECAST_HOURS_MAX)
                $h = (int)substr($echoT, 1);
                if ($h < 0) $h = 0;
                if ($h > self::FORECAST_HOURS_MAX) $h = self::FORECAST_HOURS_MAX;
                $frameIso = $this->isoUtc($baseHourTs + $h * 3600);
                $echoT = sprintf('+%d', $h);
            }
        } else {
            // ==== REAL (latest gid, no t) ====
            $mode = 'real';
            $echoT = null;
            $echoGid = null;
            // Use latest observation as frame
            $frameIso = $latest['end'] ?? $latest['start'] ?? null;
        }

        if ($frameIso === null) {
            return response()->json([
                'succeed' => false,
                'status'  => 503,
                'message' => 'frame_utc is unavailable for the requested parameters.',
            ], 503, $this->stdHeaders());
        }

        // -------- run_generated_utc (only for forecast) --------
        $runGeneratedUtc = null;
        if ($mode === 'forecast') {
            $runGeneratedUtc = $this->readForecastRunGeneratedUtc();
        }

        // -------- sources --------
        $sources = ($mode === 'forecast')
            ? ["TEMPO","AirNow","OpenAQ","Meteo"]
            : ["TEMPO"];

        // -------- clock_min (absolute delta in minutes) --------
        // Positive only. Direction (past/future) is inferred from mode.
        $frameEpoch = $this->toEpoch($frameIso);
        $clockMinAbs = null;
        if ($frameEpoch !== null) {
            $deltaSigned = (int) round(($nowTs - $frameEpoch) / 60); // past:+ , future:-
            $clockMinAbs = abs($deltaSigned);
        }

        // -------- message --------
        $message = $this->buildRealMessage($isDay, $tempoLive);

        // -------- payload --------
        $payload = [
            'succeed' => true,
            'status'  => 200,

            'product' => $product,
            'units'   => $spec['units'],

            'latest'  => $latest ? [
                'gid'   => $latest['gid'] ?? null,
                'start' => $latest['start'] ?? null,
                'end'   => $latest['end'] ?? null,
            ] : null,

            'tempo_gid' => $tempoGid,
            'now_utc'   => $nowIso,

            't'         => $echoT,
            'z'         => $z,
            'mode'      => $mode,
            'frame_utc' => $frameIso,

            // Always positive; client determines direction from mode
            'clock_min' => $clockMinAbs,

            'sources'           => $sources,
            'run_generated_utc' => $runGeneratedUtc,

            // TEMPO live observation metadata
            'tempo_age_min' => $tempoAgeMin,
            'tempo_live'    => $tempoLive,

            'is_day'  => $isDay,
            'message' => $message,
        ];

        return response()->json($payload, 200, $this->stdHeaders());
    }

    /* ===================== Helpers ===================== */

    // Builds a human-readable status message (e.g., TEMPO • Day • Live)
    private function buildRealMessage(?bool $isDay, bool $tempoLive): string
    {
        $phase = ($isDay === true) ? 'Day' : (($isDay === false) ? 'Night' : 'n/a');
        $fresh = $tempoLive ? 'Live' : 'Stale';
        return "TEMPO • {$phase} • {$fresh}";
    }

    // Normalize forecast time parameter
    private function normalizeT($t)
    {
        if ($t === null || $t === '') return null;
        $t = strtolower(trim((string)$t));
        if ($t === 'now' || $t === '+0' || $t === '0') return 'now';
        if ($t[0] === '+') {
            $h = (int)substr($t, 1);
        } else {
            if (!ctype_digit($t)) return null;
            $h = (int)$t;
        }
        if ($h < 0) $h = 0;
        if ($h > self::FORECAST_HOURS_MAX) $h = self::FORECAST_HOURS_MAX;
        return sprintf('+%d', $h);
    }

    // Units by product
    private function productSpec(string $product): array
    {
        switch ($product) {
            case 'no2':
            case 'hcho': return ['units' => 'molec/cm²'];
            case 'o3tot': return ['units' => 'DU'];
            case 'cldo4': return ['units' => 'fraction (0..1)'];
        }
        return ['units' => ''];
    }

    // Read latest TEMPO observation metadata from index.json
    private function readTempoLatest(string $product): array
    {
        $indexPath = storage_path("app/tempo/{$product}/json/index.json");
        $latest = null;
        $latestEpoch = null;

        if (is_file($indexPath)) {
            $idx = $this->readJsonFileSafely($indexPath);
            if (is_array($idx)) {
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
            }
        }

        $ageMin = null;
        if ($latestEpoch !== null) {
            $ageMin = max(0, (int)floor((time() - $latestEpoch) / 60));
        }

        return [
            'latest'  => $latest,
            'age_min' => $ageMin,
        ];
    }

    // Look up frame (ISO string) for a given gid
    private function lookupGidFrameIso(string $product, string $gid): ?string
    {
        $indexPath = storage_path("app/tempo/{$product}/json/index.json");
        if (!is_file($indexPath)) return null;
        $idx = $this->readJsonFileSafely($indexPath);
        if (!is_array($idx)) return null;
        $meta = $idx[$gid] ?? null;
        if (!is_array($meta)) return null;
        $t0 = isset($meta['t0']) ? (string)$meta['t0'] : (string)($meta['start'] ?? '');
        $t1 = isset($meta['t1']) ? (string)$meta['t1'] : (string)($meta['end'] ?? '');
        return $t1 ?: ($t0 ?: null);
    }

    // Read forecast run generation timestamp
    private function readForecastRunGeneratedUtc(): ?string
    {
        $base = storage_path('app/weather/meteo/json');
        $idxPath = "{$base}/index.json";
        $ts = null;

        if (is_file($idxPath)) {
            $idx = $this->readJsonFileSafely($idxPath);
            if (is_array($idx)) {
                foreach (['generated_at', 'updated_at', 'created_at', 'latest_run_ts'] as $k) {
                    if (!empty($idx[$k]) && is_string($idx[$k])) {
                        $ts = $this->toEpoch($idx[$k]);
                        if ($ts) break;
                    }
                }
            }
            if ($ts === null) {
                $ts = @filemtime($idxPath) ?: null;
            }
        }
        return $ts ? $this->isoUtc($ts) : null;
    }

    // Safe JSON file reader with retries
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

    // Convert ISO UTC string to epoch seconds
    private function toEpoch(?string $iso): ?int
    {
        if (!$iso || !is_string($iso)) return null;
        $t = @strtotime($iso);
        return $t ? (int)$t : null;
    }

    // Convert epoch to ISO UTC string
    private function isoUtc(int $ts): string
    {
        return gmdate('Y-m-d\TH:i:s\Z', $ts);
    }

    // Standard API response headers
    private function stdHeaders(): array
    {
        return [
            // Short cache lifetime to reflect quick-changing data
            'Cache-Control' => 'public, max-age=60, s-maxage=60',
            'Access-Control-Allow-Origin' => '*',
            'Content-Type' => 'application/json; charset=utf-8',
        ];
    }

    // Determine if given location/time is daytime
    private function isDayAt(float $lat, float $lon, int $ts): ?bool
    {
        $info = @date_sun_info($ts, $lat, $lon);
        if (!is_array($info)) return null;

        $sr = $info['sunrise'] ?? false;
        $ss = $info['sunset']  ?? false;

        if (!$sr || !$ss) {
            $dl = (int)($info['day_length'] ?? 0);
            if ($dl > 0) return true;
            if ($dl === 0) return false;
            return null;
        }
        return ($ts >= $sr && $ts <= $ss);
    }
}
