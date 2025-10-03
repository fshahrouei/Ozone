<?php

namespace App\Http\Controllers\API\V1\Frontend\AirQualities;

use Illuminate\Http\Request;

/**
 * API: Stations (Viewport)
 *
 * GET /api/v1/frontend/air-quality/stations
 *
 * Purpose:
 *   Return counts, brief info, and exact locations of ground stations
 *   within a viewport (bbox) for supported products (no2, o3).
 *
 * Inputs (Query):
 *   - product:   no2 | o3 | o3tot  (default: no2)  [o3tot -> o3]
 *   - bbox:      "W,S,E,N"   (required)
 *   - max_age_h: maximum allowed data age in hours (default: 6.0) — reject files older than this
 *   - limit:     maximum number of points to return (default: 2000)
 *   - points:    1|0  (default 1) — if 0, only summary is returned (no points list)
 *   - provider:  optional provider filter (e.g., OpenAQ, AirNow) — comma-separated
 *
 * Output (JSON):
 * {
 *   "succeed": true,
 *   "status": 200,
 *   "product": "no2",
 *   "bbox": {"w":..., "s":..., "e":..., "n":...},
 *   "source": {
 *     "path": ".../hours/2025-09-14T18.json.gz",
 *     "ts": "2025-09-14T18:00:00Z",
 *     "why": "ok"
 *   },
 *   "summary": {
 *     "count_total":  312,       // total points (before limit)
 *     "count_return": 2000,      // returned points (after limit / points=0 → 0)
 *     "providers": [
 *        {"name":"OpenAQ","count": 290},
 *        {"name":"AirNow","count": 22}
 *     ],
 *     "age_h_mean": 1.23,        // if age is available
 *     "bounds": {"w":..., "s":..., "e":..., "n":...}
 *   },
 *   "points": [
 *      {"lat": 38.90, "lon": -77.04, "val": 3.2e15, "age_h": 1.1, "provider": "OpenAQ"},
 *      ...
 *   ]
 * }
 *
 * Headers:
 *   - Access-Control-Allow-Origin: *
 *   - X-Stations-Count-Total
 *   - X-Stations-Count-Return
 *   - X-Stations-Source-Ts
 *   - X-Stations-Source-Path
 */
class Stations
{
    /* Allowed products (stations) */
    private const PRODUCTS = ['no2','o3','o3tot'];

    public function build(Request $request)
    {
        try {
            /* ---------- 1) Params ---------- */
            $product = strtolower((string)$request->query('product', 'no2'));
            if (!in_array($product, self::PRODUCTS, true)) {
                return $this->jerr(422, 'invalid product (one of: no2 | o3 | o3tot)');
            }
            // Map o3tot → o3 (stations are stored under o3)
            if ($product === 'o3tot') $product = 'o3';

            $bboxStr = (string)$request->query('bbox', '');
            $bbox = $this->parseBbox($bboxStr);
            if (!$bbox) {
                return $this->jerr(400, 'invalid bbox (expect "W,S,E,N")');
            }
            [$Wdeg,$Sdeg,$Edeg,$Ndeg] = $bbox;

            $maxAgeH = (float)$request->query('max_age_h', 6.0);
            if (!is_finite($maxAgeH) || $maxAgeH < 0.0) $maxAgeH = 6.0;

            $limit   = (int)$request->query('limit', 2000);
            if ($limit <= 0) $limit = 2000;

            $withPoints = ((int)$request->query('points', 1) === 1);

            $providersFilter = trim((string)$request->query('provider', ''));
            $providersSet = null;
            if ($providersFilter !== '') {
                $providersSet = [];
                foreach (explode(',', $providersFilter) as $p) {
                    $t = trim($p);
                    if ($t !== '') $providersSet[strtolower($t)] = true;
                }
            }

            $now = time();

            /* ---------- 2) Load stations payload ---------- */
            $load = $this->loadStationsForProduct($product, $maxAgeH, $now);
            $pointsAll = $load['points'] ?? [];
            $srcPath   = $load['src']    ?? 'na';
            $srcTs     = $load['ts']     ?? 'na';
            $why       = $load['why']    ?? 'empty_data';
            $unit      = $load['unit']   ?? null; // may be used later; not echoed for now

            // If empty, respond with an empty-but-successful payload and an explanatory "why"
            if (empty($pointsAll)) {
                $out = [
                    'succeed' => true,
                    'status'  => 200,
                    'product' => $product,
                    'bbox'    => ['w'=>$Wdeg,'s'=>$Sdeg,'e'=>$Edeg,'n'=>$Ndeg],
                    'source'  => ['path'=>$srcPath,'ts'=>$srcTs,'why'=>$why],
                    'summary' => [
                        'count_total'  => 0,
                        'count_return' => 0,
                        'providers'    => [],
                        'age_h_mean'   => null,
                        'bounds'       => ['w'=>$Wdeg,'s'=>$Sdeg,'e'=>$Edeg,'n'=>$Ndeg],
                    ],
                    'points' => [],
                ];
                return response()->json($out, 200, [
                    'Access-Control-Allow-Origin' => '*',
                    'Content-Type' => 'application/json; charset=utf-8',
                    'X-Stations-Count-Total'  => '0',
                    'X-Stations-Count-Return' => '0',
                    'X-Stations-Source-Ts'    => (string)$srcTs,
                    'X-Stations-Source-Path'  => (string)$srcPath,
                ]);
            }

            /* ---------- 3) Filter by bbox (+ optional provider) ---------- */
            $filtered = [];
            $ageSum = 0.0; $ageCnt = 0;
            foreach ($pointsAll as $p) {
                $lat = isset($p['lat']) ? (float)$p['lat'] : NAN;
                $lon = isset($p['lon']) ? (float)$p['lon'] : NAN;
                if (!is_finite($lat) || !is_finite($lon)) continue;
                if ($lon < $Wdeg || $lon > $Edeg || $lat < $Sdeg || $lat > $Ndeg) continue;

                if ($providersSet) {
                    $prov = isset($p['provider']) ? strtolower((string)$p['provider']) : '';
                    if ($prov === '' || !isset($providersSet[$prov])) continue;
                }

                $row = ['lat'=>$lat, 'lon'=>$lon];

                if (isset($p['val']) && is_numeric($p['val'])) {
                    $row['val'] = (float)$p['val'];
                } elseif (isset($p['value']) && is_numeric($p['value'])) {
                    $row['val'] = (float)$p['value'];
                }

                if (isset($p['age_h']) && is_numeric($p['age_h'])) {
                    $row['age_h'] = (float)$p['age_h'];
                    $ageSum += (float)$p['age_h'];
                    $ageCnt++;
                }

                if (isset($p['provider']) && is_string($p['provider']) && $p['provider']!=='') {
                    $row['provider'] = (string)$p['provider'];
                }

                $filtered[] = $row;
            }

            $countTotal = count($filtered);

            /* ---------- 4) Limit & providers summary ---------- */
            $providersSummary = [];
            if ($countTotal > 0) {
                $pc = [];
                foreach ($filtered as $r) {
                    $k = strtolower((string)($r['provider'] ?? 'unknown'));
                    if (!isset($pc[$k])) $pc[$k] = 0;
                    $pc[$k]++;
                }
                foreach ($pc as $name=>$cnt) {
                    $providersSummary[] = ['name'=>$name, 'count'=>$cnt];
                }
                usort($providersSummary, fn($a,$b)=> $b['count'] <=> $a['count']);
            }

            $ageMean = ($ageCnt>0) ? ($ageSum/$ageCnt) : null;

            $returned = [];
            if ($withPoints && $countTotal > 0) {
                // If too many points, truncate
                if ($countTotal > $limit) {
                    $returned = array_slice($filtered, 0, $limit);
                } else {
                    $returned = $filtered;
                }
            }
            $countReturn = $withPoints ? count($returned) : 0;

            /* ---------- 5) Build response ---------- */
            $out = [
                'succeed' => true,
                'status'  => 200,
                'product' => $product,
                'bbox'    => ['w'=>$Wdeg,'s'=>$Sdeg,'e'=>$Edeg,'n'=>$Ndeg],
                'source'  => [
                    'path' => $srcPath,
                    'ts'   => $srcTs,
                    'why'  => $why
                ],
                'summary' => [
                    'count_total'  => $countTotal,
                    'count_return' => $countReturn,
                    'providers'    => $providersSummary,
                    'age_h_mean'   => is_null($ageMean) ? null : (float)sprintf('%.4f',$ageMean),
                    'bounds'       => ['w'=>$Wdeg,'s'=>$Sdeg,'e'=>$Edeg,'n'=>$Ndeg],
                ],
                'points' => $withPoints ? $returned : [],
            ];

            return response()->json($out, 200, [
                'Access-Control-Allow-Origin' => '*',
                'Content-Type' => 'application/json; charset=utf-8',
                'Cache-Control' => 'public, max-age=120',
                'X-Stations-Count-Total'  => (string)$countTotal,
                'X-Stations-Count-Return' => (string)$countReturn,
                'X-Stations-Source-Ts'    => (string)$srcTs,
                'X-Stations-Source-Path'  => (string)$srcPath,
            ]);

        } catch (\Throwable $e) {
            return $this->jerr(500, 'internal error', ['error'=>$e->getMessage()]);
        }
    }

    /* ======================== Helpers ======================== */

    private function jerr(int $status, string $msg, array $extra = [])
    {
        $out = array_merge(['succeed'=>false,'status'=>$status,'message'=>$msg], $extra);
        return response()->json($out, $status, [
            'Access-Control-Allow-Origin' => '*',
            'Content-Type' => 'application/json; charset=utf-8'
        ]);
    }

    private function parseBbox(string $s)
    {
        if ($s==='') return null;
        $p = array_map('trim', explode(',', $s));
        if (count($p)!==4) return null;
        $W = (float)$p[0]; $S=(float)$p[1]; $E=(float)$p[2]; $N=(float)$p[3];
        if (!is_finite($W)||!is_finite($S)||!is_finite($E)||!is_finite($N)) return null;
        if ($E <= $W || $N <= $S) return null;
        return [$W,$S,$E,$N];
    }

    private function stationDirFor(string $product): string {
        // no2 → no2 , o3tot|o3 → o3
        return ($product === 'o3tot' || $product === 'o3') ? 'o3' : 'no2';
    }

    /**
     * Load the nearest valid hourly stations file within the allowed maximum age.
     * If index.json is missing, read from hours/* (json or json.gz).
     * Output is normalized to points/val/age_h/provider/ts/unit + src path + why.
     */
    private function loadStationsForProduct(string $product, float $maxAgeH, int $now): array
    {
        $dir  = $this->stationDirFor($product);
        $base = storage_path("app/stations/{$dir}/json");

        $indexPath = "{$base}/index.json";
        $idx = $this->readJsonSimple($indexPath);

        $candTimes = [];
        $push = function(string $ts) use (&$candTimes) {
            $t = trim($ts);
            $hasZ = (substr($t,-1)==='Z' || substr($t,-1)==='z');
            $tsZ   = $hasZ ? substr($t,0,-1).'Z' : ($t.'Z');
            $tsNoZ = $hasZ ? substr($t,0,-1) : $t;
            $candTimes[] = ['norm'=>$tsZ,'z'=>$tsZ,'noz'=>$tsNoZ];
        };

        if (is_array($idx)) {
            if (isset($idx['latestHour']) && is_string($idx['latestHour'])) $push($idx['latestHour']);
            if (isset($idx['hours']) && is_array($idx['hours'])) {
                foreach ($idx['hours'] as $h) if (is_string($h)) $push($h);
            }
        } else {
            $glob1 = glob("{$base}/hours/*.json") ?: [];
            $glob2 = glob("{$base}/hours/*.json.gz") ?: [];
            $files = array_merge($glob1, $glob2);
            rsort($files);
            foreach ($files as $fp) {
                $name = basename($fp);
                $ts = str_replace(['.json.gz','.json'], '', $name);
                if ($ts) $push($ts);
            }
        }

        // unique + desc
        $seen=[]; $cand2=[];
        foreach ($candTimes as $c) { if (isset($seen[$c['norm']])) continue; $seen[$c['norm']]=1; $cand2[]=$c; }
        usort($cand2, fn($a,$b)=>strcmp($b['norm'],$a['norm']));

        foreach ($cand2 as $c) {
            $paths = [
                "{$base}/hours/{$c['z']}.json",
                "{$base}/hours/{$c['z']}.json.gz",
                "{$base}/hours/{$c['noz']}.json",
                "{$base}/hours/{$c['noz']}.json.gz",
            ];
            foreach ($paths as $p) {
                $payload = $this->readJsonSimple($p);
                if ($payload === null) {
                    $txt = $this->readTextPossiblyGz($p);
                    if ($txt !== null) $payload = $this->tryParseNdjsonOrCsv($txt);
                }
                if ($payload === null) continue;

                $norm = $this->normalizeStationsPayload($payload, $c['z']);
                $pts = $norm['points'] ?? [];
                if (!empty($pts)) {
                    // Check the data age relative to "now"
                    if (isset($norm['ts']) && is_string($norm['ts'])) {
                        $ts = strtotime(rtrim($norm['ts'],'Z').'Z');
                        if ($ts !== false) {
                            $ageH = max(0.0, ($now - $ts)/3600.0);
                            if ($ageH > $maxAgeH) {
                                // Too old; try the previous file
                                continue;
                            }
                        }
                    }
                    $norm['src'] = $p;
                    return $norm;
                }
            }
        }

        return ['points'=>[], 'unit'=>null, 'ts'=>null, 'why'=>'empty_data', 'src'=>"{$base}/hours/*"];
    }

    /**
     * Normalize heterogeneous inputs (array, FeatureCollection, NDJSON/CSV) into
     * a standard structure: points/val/age_h/provider + unit + ts.
     */
    private function normalizeStationsPayload($payload, ?string $fileTs): array
    {
        $out = ['points'=>[], 'unit'=>null, 'ts'=>$fileTs, 'why'=>'ok'];
        $unit = null;

        if (is_array($payload) && empty($payload)) {
            return ['points'=>[], 'unit'=>null, 'ts'=>$fileTs, 'why'=>'empty_data'];
        }

        // Case: simple array of objects
        if (is_array($payload) && isset($payload[0]) && is_array($payload[0])) {
            foreach ($payload as $p) {
                $lat = $p['lat'] ?? ($p['latitude'] ?? null);
                $lon = $p['lon'] ?? ($p['longitude'] ?? null);
                $val = $p['val'] ?? ($p['value'] ?? ($p['concentration'] ?? null));
                $ts  = $p['ts']  ?? ($p['time'] ?? ($p['timestamp'] ?? null));
                $prov= $p['provider'] ?? null;

                $age = null;
                if (is_string($ts)) { $tsp = strtotime($ts); if ($tsp !== false) $age = max(0.0,(time()-$tsp)/3600.0); }

                if (!$unit) $unit = $p['units'] ?? ($p['unit'] ?? null);

                if (is_numeric($lat) && is_numeric($lon) && is_numeric($val)) {
                    $pt = ['lat'=>(float)$lat,'lon'=>(float)$lon,'val'=>(float)$val,'age_h'=>$age];
                    if ($prov) $pt['provider'] = $prov;
                    $out['points'][] = $pt;
                }
            }
            $out['unit'] = $unit ?? null;
            if (empty($out['points'])) $out['why'] = 'empty_data';
            return $out;
        }

        // Case: dictionary-like object
        if (is_array($payload) && empty($payload[0]) && count($payload) > 0) {
            foreach (array_values($payload) as $p) {
                if (!is_array($p)) continue;

                $lat = $p['lat'] ?? ($p['latitude'] ?? ($p['Latitude'] ?? null));
                $lon = $p['lon'] ?? ($p['longitude']?? ($p['Longitude']?? null));

                if ((!is_numeric($lat) || !is_numeric($lon)) && isset($p['coords']) && is_array($p['coords'])) {
                    $lat = $p['coords']['lat'] ?? $lat;
                    $lon = $p['coords']['lon'] ?? $lon;
                }
                if ((!is_numeric($lat) || !is_numeric($lon)) && isset($p['geometry']['coordinates'][0])) {
                    $lon = $p['geometry']['coordinates'][0];
                    $lat = $p['geometry']['coordinates'][1] ?? null;
                }

                $val = $p['val'] ?? ($p['value'] ?? ($p['concentration'] ?? null));
                $ts  = $p['ts']  ?? ($p['time'] ?? ($p['timestamp'] ?? ($p['DateTime'] ?? null)));
                if (!$unit) $unit = $p['units'] ?? ($p['unit'] ?? ($p['Unit'] ?? ($p['Units'] ?? null)));
                $prov= $p['provider'] ?? null;

                $age = null;
                if (is_string($ts)) { $tsp = strtotime($ts); if ($tsp!==false) $age=max(0.0,(time()-$tsp)/3600.0); }

                if (is_numeric($lat) && is_numeric($lon) && is_numeric($val)) {
                    $pt = ['lat'=>(float)$lat,'lon'=>(float)$lon,'val'=>(float)$val,'age_h'=>$age];
                    if ($prov) $pt['provider'] = $prov;
                    $out['points'][] = $pt;
                }
            }
            $out['unit'] = $unit ?? null;
            if (empty($out['points'])) $out['why'] = 'empty_data';
            return $out;
        }

        // Case: GeoJSON FeatureCollection
        if (is_array($payload) && ($payload['type'] ?? null) === 'FeatureCollection' && isset($payload['features'])) {
            foreach ($payload['features'] as $f) {
                $geom = $f['geometry'] ?? null;
                $prop = $f['properties'] ?? [];
                if (!is_array($geom) || ($geom['type'] ?? null) !== 'Point') continue;
                $coords = $geom['coordinates'] ?? null;
                if (!is_array($coords) || count($coords) < 2) continue;

                $lon = $coords[0]; $lat = $coords[1];
                $val = $prop['val'] ?? ($prop['value'] ?? ($prop['concentration'] ?? null));
                $age = $prop['age_h'] ?? null;
                if (!$unit) $unit = $prop['unit'] ?? ($prop['units'] ?? null);

                if (is_numeric($lat) && is_numeric($lon) && is_numeric($val)) {
                    $pt = ['lat'=>(float)$lat,'lon'=>(float)$lon,'val'=>(float)$val,'age_h'=>$age];
                    if (isset($prop['provider'])) $pt['provider'] = $prop['provider'];
                    $out['points'][] = $pt;
                }
            }
            $out['unit'] = $unit ?? null;
            if (empty($out['points'])) $out['why'] = 'empty_data';
            return $out;
        }

        // Case: NDJSON/CSV as parsed by tryParseNdjsonOrCsv
        if (is_array($payload) && isset($payload['_ndjson']) && is_array($payload['_ndjson'])) {
            foreach ($payload['_ndjson'] as $p) {
                $lat = $p['lat'] ?? ($p['latitude'] ?? null);
                $lon = $p['lon'] ?? ($p['longitude'] ?? null);
                $val = $p['val'] ?? ($p['value'] ?? ($p['concentration'] ?? null));
                $ts  = $p['ts'] ?? ($p['time'] ?? ($p['timestamp'] ?? null));
                $age = null;
                if (is_string($ts)) { $tsp = strtotime($ts); if ($tsp !== false) $age = max(0.0,(time()-$tsp)/3600.0); }
                if (!$unit) $unit = $p['units'] ?? ($p['unit'] ?? null);
                if (is_numeric($lat) && is_numeric($lon) && is_numeric($val)) {
                    $row = ['lat'=>(float)$lat,'lon'=>(float)$lon,'val'=>(float)$val,'age_h'=>$age];
                    if (isset($p['provider'])) $row['provider'] = $p['provider'];
                    $out['points'][] = $row;
                }
            }
            if (empty($out['points'])) $out['why'] = 'empty_data';
            $out['unit'] = $unit ?? null;
            return $out;
        }

        // Case: single record
        if (is_array($payload) && (isset($payload['lat']) || isset($payload['latitude']))) {
            $lat = $payload['lat'] ?? $payload['latitude'];
            $lon = $payload['lon'] ?? ($payload['longitude'] ?? null);
            $val = $payload['val'] ?? ($payload['value'] ?? ($payload['concentration'] ?? null));
            $ts  = $payload['ts'] ?? ($payload['time'] ?? ($payload['timestamp'] ?? null));
            $age = null;
            if (is_string($ts)) { $tsp = strtotime($ts); if ($tsp !== false) $age = max(0.0,(time()-$tsp)/3600.0); }
            $unit = $payload['units'] ?? ($payload['unit'] ?? null);
            if (is_numeric($lat) && is_numeric($lon) && is_numeric($val)) {
                $out['points'][] = ['lat'=>(float)$lat,'lon'=>(float)$lon,'val'=>(float)$val,'age_h'=>$age];
                $out['unit'] = $unit ?? null;
                return $out;
            }
        }

        return ['points'=>[], 'unit'=>null, 'ts'=>$fileTs, 'why'=>'format_unknown'];
    }

    /* ======================== JSON readers ======================== */

    private function readJsonSimple(string $path)
    {
        try {
            $raw = $this->readTextPossiblyGz($path);
            if ($raw === null) return null;
            if (substr($raw, 0, 3) === "\xEF\xBB\xBF") $raw = substr($raw, 3);
            $raw = $this->jsonSanitize($raw);
            $js  = json_decode($raw, true, 1024, JSON_INVALID_UTF8_IGNORE);
            return (json_last_error() === JSON_ERROR_NONE) ? $js : null;
        } catch (\Throwable $e) {
            return null;
        }
    }

    private function jsonSanitize(string $s): string
    {
        $patterns = [
            '/(?<=[:,\[\{\s])NaN(?=[,\]\}\s])/i',
            '/(?<=[:,\[\{\s])Infinity(?=[,\]\}\s])/i',
            '/(?<=[:,\[\{\s])-Infinity(?=[,\]\}\s])/i',
        ];
        $s = preg_replace($patterns, 'null', $s);
        $s = preg_replace('/,\s*([\]\}])/', '$1', $s);
        return $s;
    }

    private function readTextPossiblyGz(string $path): ?string
    {
        $gz = $path . '.gz';
        if (is_file($path)) {
            $txt = @file_get_contents($path);
            return ($txt === false) ? null : $txt;
        }
        if (is_file($gz)) {
            $fp = @gzopen($gz, 'rb');
            if (!$fp) return null;
            $buf = '';
            while (!gzeof($fp)) {
                $chunk = gzread($fp, 1 << 20);
                if ($chunk === false) { gzclose($fp); return null; }
                $buf .= $chunk;
                if (strlen($buf) > 600 * 1024 * 1024) { gzclose($fp); return null; }
            }
            gzclose($fp);
            return $buf;
        }
        return null;
    }

    private function tryParseNdjsonOrCsv(string $text) {
        $text = trim($text);
        if ($text==='') return null;
        $lines = preg_split("/\r\n|\n|\r/", $text);
        $items = [];
        $commaHeaders = null;

        foreach ($lines as $i=>$ln) {
            $ln = trim($ln);
            if ($ln==='') continue;

            // NDJSON
            if ($ln[0]==='{' && substr($ln,-1)==='}') {
                $js = json_decode($ln, true);
                if (is_array($js)) { $items[] = $js; continue; }
            }

            // CSV (first row is header)
            if ($i===0 && strpos($ln, ',')!==false) {
                $commaHeaders = array_map('trim', explode(',', $ln));
                continue;
            }
            if ($commaHeaders !== null) {
                $cols = array_map('trim', explode(',', $ln));
                $row = [];
                foreach ($commaHeaders as $k=>$h) {
                    $row[$h] = $cols[$k] ?? null;
                }
                $items[] = $row;
                continue;
            }
        }

        if (!empty($items)) return ['_ndjson' => $items];
        return null;
    }
}
