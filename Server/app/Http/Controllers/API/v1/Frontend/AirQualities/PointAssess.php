<?php

namespace App\Http\Controllers\API\V1\Frontend\AirQualities;

use Illuminate\Http\Request;
use Illuminate\Support\Arr;
use Illuminate\Support\Facades\App;
use Illuminate\Support\Facades\Http; // <-- for Http::pool()
use App\Http\Controllers\API\V1\Frontend\AirQualities\ForecastGrids;

use Illuminate\Http\Client\Pool;
use Illuminate\Http\Client\Response as HttpResponse;
use Illuminate\Support\Facades\Log;
use Throwable;

class PointAssess
{
    /**
     * Disease / sensitive groups and sensitivity weights per product (0..1)
     * NOTE: purely heuristic; used for health section aggregation.
     */
    private array $DISEASE_WEIGHTS = [
        [
            'id'    => 'asthma',
            'title' => 'Asthma',
            'weights' => ['no2'=>0.50,'hcho'=>0.35,'o3tot'=>0.15,'cldo4'=>0.00],
            'note'  => 'Higher risk with NO₂ and formaldehyde; ozone can irritate airways.',
        ],
        [
            'id'    => 'copd',
            'title' => 'COPD',
            'weights' => ['no2'=>0.45,'hcho'=>0.25,'o3tot'=>0.30,'cldo4'=>0.00],
            'note'  => 'Chronic respiratory disease sensitivity to NO₂ & O₃.',
        ],
        [
            'id'    => 'cvd',
            'title' => 'Cardiovascular disease',
            'weights' => ['no2'=>0.55,'hcho'=>0.20,'o3tot'=>0.25,'cldo4'=>0.00],
            'note'  => 'Traffic-related NO₂ linked to CV stress; O₃ adds oxidative stress.',
        ],
        [
            'id'    => 'children',
            'title' => 'Children',
            'weights' => ['no2'=>0.45,'hcho'=>0.35,'o3tot'=>0.20,'cldo4'=>0.00],
            'note'  => 'Developing lungs more sensitive to irritants.',
        ],
        [
            'id'    => 'pregnancy',
            'title' => 'Pregnancy',
            'weights' => ['no2'=>0.40,'hcho'=>0.30,'o3tot'=>0.30,'cldo4'=>0.00],
            'note'  => 'Some pollutants associated with adverse outcomes.',
        ],
        [
            'id'    => 'elderly',
            'title' => 'Elderly',
            'weights' => ['no2'=>0.40,'hcho'=>0.25,'o3tot'=>0.35,'cldo4'=>0.00],
            'note'  => 'Age-related vulnerability to respiratory/oxidative stress.',
        ],
        [
            'id'    => 'allergies',
            'title' => 'Allergic rhinitis',
            'weights' => ['no2'=>0.30,'hcho'=>0.45,'o3tot'=>0.25,'cldo4'=>0.00],
            'note'  => 'Formaldehyde/ozone can irritate mucosa.',
        ],
        [
            'id'    => 'lung_cancer_longterm',
            'title' => 'Long-term lung risk',
            'weights' => ['no2'=>0.35,'hcho'=>0.45,'o3tot'=>0.20,'cldo4'=>0.00],
            'note'  => 'Chronic exposure relevance; proxy only.',
        ],
        [
            'id'    => 'athletes',
            'title' => 'Outdoor athletes',
            'weights' => ['no2'=>0.35,'hcho'=>0.25,'o3tot'=>0.40,'cldo4'=>0.00],
            'note'  => 'Ozone is notable during exertion.',
        ],
        [
            'id'    => 'general',
            'title' => 'General population',
            'weights' => ['no2'=>0.40,'hcho'=>0.30,'o3tot'=>0.30,'cldo4'=>0.00],
            'note'  => 'Aggregate sensitivity profile.',
        ],
    ];

    /**
     * Inputs (GET):
     * - lat, lon (required)
     * - products=no2,hcho,o3tot,cldo4 (optional; default: no2,hcho,o3tot)
     * - t or t_hours (future 0..12h); accepts: +6 | 6 | +6h | 6h | t_hours=6
     * - z (optional; clamped effective 9..11)
     * - radius_km (optional; default ~0.35° ≈ ~39km at mid-latitudes)
     * - weights[no2]=0.5&weights[hcho]=0.25&... (optional; for overall score)
     * - debug=1 (optional; verbose debugging payload)
     *
     * Output: JSON with per-product assessments + overall + health sections.
     */
    public function build(Request $request)
    {
        try {
            // 1) Parse inputs
            [$lat, $lon] = $this->parsePoint($request);
            $products     = $this->parseProducts($request);
            $h            = $this->parseTHours($request);         // 0..12
            $tCanonical   = '+' . $h;                             // for ForecastGrids
            $zEff         = $this->clampZEff($request->query('z', 9)); // 9..11
            $debugFlag    = $this->toBool($request->query('debug', 0));

            // Build bbox around point, then clamp to NA domain
            $bbox = $this->buildbboxAroundPoint($lat, $lon, $request);
            $bbox = $this->clampBboxToNA($bbox);

            // Weights for overall score
            $weights = $this->parseWeights($request, $products);

            // 2) Query ForecastGrids concurrently for all requested products
            //    - We call HTTP endpoint to leverage PHP-FPM worker parallelism.
            //    - Stations are only effective for NO2 in ForecastGrids.
            [$perProduct, $perProductScore10, $anyOk, $anyFail] =
                $this->assessProductsFutureConcurrent(
                    products: $products,
                    lat: $lat,
                    lon: $lon,
                    zEff: $zEff,
                    tCanonical: $tCanonical,
                    bbox: $bbox,
                    debug: $debugFlag,
                );

            // 3) Overall weighted score (if any product succeeded)
            $overall = null;
            if ($anyOk) {
                $overall = $this->buildOverallScores($perProductScore10, $weights);
            } else {
                $overall = [
                    'succeed' => false,
                    'status'  => 204,
                    'message' => 'no data in bbox for all requested products',
                    'weights' => $weights,
                ];
            }

            // 4) Health section
            $health = $this->buildHealthSection($perProductScore10, $products);

            // 5) Final response assembly
            $nowIso = gmdate('c');
            $response = [
                'succeed' => true,
                'status'  => 200,
                'meta'    => [
                    'api'         => 'point-assess',
                    'version'     => '1.1',
                    'mode'        => 'future', // future-only assessment
                    'generated_at'=> $nowIso,
                    'units'       => 'product-specific',
                ],
                'request' => [
                    'lat'      => $lat,
                    'lon'      => $lon,
                    't'        => $tCanonical,       // +H
                    'z_eff'    => $zEff,             // 9..11
                    'products' => $products,
                    'bbox'     => ['w' => $bbox[0], 's' => $bbox[1], 'e' => $bbox[2], 'n' => $bbox[3]],
                    'weights'  => $weights,
                ],
                'point'     => ['lat'=>$lat,'lon'=>$lon],
                'products'  => $perProduct,
                'overall'   => $overall,
                'health'    => $health,
            ];

            if ($anyFail && $anyOk) {
                $response['meta']['partial'] = true;
                $response['meta']['notes'][] = 'some products failed or returned empty cells';
            }
            if (!$anyOk) {
                // Keep API HTTP status 200 by contract; overall conveys "no data".
                $response['meta']['notes'][] = 'no-data for all products in requested bbox';
            }

            if ($debugFlag) {
                $response['debug'] = [
                    'bbox_deg'   => $bbox,
                    'z_eff_note' => 'clamped to 9..11 (8=>9, >=12=>11)',
                    't_note'     => 't normalized to +H',
                    'concurrency'=> 'Http::pool() used for per-product ForecastGrids',
                ];
            }

            return response()->json($response, 200);

        } catch (\InvalidArgumentException $e) {
            return response()->json([
                'succeed' => false,
                'status'  => 400,
                'message' => $e->getMessage(),
            ], 400);
        } catch (\Throwable $e) {
            return response()->json([
                'succeed' => false,
                'status'  => 500,
                'message' => 'internal error',
                'error'   => App::environment('production') ? null : $e->getMessage(),
            ], 500);
        }
    }

    // -------------------------- Concurrency: assess multiple products --------------------------

    /**
     * Fire ForecastGrids concurrently (Http::pool) for all products.
     * - Uses the public route to allow true parallelism across FPM workers.
     * - Stations are only applied for NO2 (as per ForecastGrids logic).
     * - Meteo is enabled for all; handled inside ForecastGrids.
     *
     * @return array [$perProduct, $perProductScore10, $anyOk, $anyFail]
     */


private function assessProductsFutureConcurrent(
    array $products,
    float $lat,
    float $lon,
    int $zEff,
    string $tCanonical,
    array $bbox,
    bool $debug
): array {
    $perProduct = [];
    $perProductScore10 = [];
    $anyOk = false;
    $anyFail = false;

    // --- Build absolute URL robustly
    try {
        $fgUrl = route('api.v1.frontend.air-quality.forecastGrids');
    } catch (Throwable $e) {
        $base = rtrim((string) config('app.url'), '/');
        if ($base === '') {
            $req    = request();
            $scheme = $req->isSecure() ? 'https' : 'http';
            $host   = $req->getHost();
            $base   = $host ? ($scheme.'://'.$host) : 'http://127.0.0.1';
        }
        $fgUrl = $base.'/api/v1/frontend/air-quality/forecast-grids';
    }

    $bboxStr = implode(',', $bbox);

    // --- Prepare query sets
    $requests = [];
    foreach ($products as $p) {
        $requests[$p] = [
            'product'        => $p,
            'z'              => $zEff,
            't'              => $tCanonical,     // "+H"
            'bbox'           => $bboxStr,
            'format'         => 'json',
            'stations'       => ($p === 'no2') ? 1 : 0,
            'stations_debug' => $debug ? 1 : 0,
            'meteo'          => 1,
            'meteo_debug'    => $debug ? 1 : 0,
        ];
    }

    // --- Fire pool (slightly larger timeouts for stability)
    $responses = Http::acceptJson()
        ->retry(1, 200)
        ->timeout(25)        // total per request
        ->connectTimeout(6)  // TCP connect
        ->pool(function (Pool $pool) use ($fgUrl, $requests) {
            $bag = [];
            foreach ($requests as $key => $params) {
                $bag[$key] = $pool->as($key)->get($fgUrl, $params);
            }
            return $bag;
        });

    // --- Parse/normalize with strong guards + logging
    foreach ($products as $p) {
        $resp = $responses[$p] ?? null;

        // A) Exception item from pool
        if ($resp instanceof Throwable) {
            Log::warning('[PointAssess] pool exception', [
                'product' => $p,
                'type'    => get_class($resp),
                'msg'     => $resp->getMessage(),
                'url'     => $fgUrl,
                'query'   => $requests[$p],
            ]);

            $perProduct[$p] = [
                'product' => $p,
                'succeed' => false,
                'status'  => 0,
                'message' => 'connection error',
                'error'   => get_class($resp).': '.$resp->getMessage(),
            ];
            $anyFail = true;
            continue;
        }

        // B) Unexpected type (should be Illuminate\Http\Client\Response)
        if (!$resp instanceof HttpResponse) {
            Log::error('[PointAssess] pool unexpected item', [
                'product' => $p,
                'type'    => is_object($resp) ? get_class($resp) : gettype($resp),
                'url'     => $fgUrl,
                'query'   => $requests[$p],
            ]);

            $perProduct[$p] = [
                'product' => $p,
                'succeed' => false,
                'status'  => 502,
                'message' => 'unexpected pool item (not a Response)',
            ];
            $anyFail = true;
            continue;
        }

        // C) Normal HTTP response
        if (!$resp->ok()) {
            // truncate body for log
            $bodySnippet = substr((string) $resp->body(), 0, 500);
            Log::warning('[PointAssess] forecast-grids http not ok', [
                'product' => $p,
                'status'  => $resp->status(),
                'url'     => $fgUrl,
                'query'   => $requests[$p],
                'body'    => $bodySnippet,
            ]);

            $perProduct[$p] = [
                'product' => $p,
                'succeed' => false,
                'status'  => $resp->status(),
                'message' => 'forecast-grids request failed',
            ];
            $anyFail = true;
            continue;
        }

        $json = $resp->json();
        if (!is_array($json) || ($json['succeed'] ?? false) !== true) {
            Log::info('[PointAssess] forecast-grids logical fail', [
                'product' => $p,
                'status'  => Arr::get($json, 'status', 502),
                'msg'     => Arr::get($json, 'message', 'no data'),
                'url'     => $fgUrl,
                'query'   => $requests[$p],
            ]);

            $perProduct[$p] = [
                'product' => $p,
                'succeed' => false,
                'status'  => Arr::get($json, 'status', 502),
                'message' => Arr::get($json, 'message', 'no data'),
            ];
            $anyFail = true;
            continue;
        }

        $cells = Arr::get($json, 'cells', []);
        if (empty($cells)) {
            Log::info('[PointAssess] no cells', [
                'product' => $p,
                'url'     => $fgUrl,
                'query'   => $requests[$p],
            ]);

            $perProduct[$p] = [
                'product' => $p,
                'succeed' => false,
                'status'  => 204,
                'message' => 'no cells',
                'meta'    => Arr::only($json, ['product','units','mode','z','t','grid_deg','bucket_deg','domain','bbox','bbox_effective','palette']),
            ];
            $anyFail = true;
            continue;
        }

        // Nearest cell + scoring
        [$closest, $distKm] = $this->nearestCell($lat, $lon, $cells);
        $domainMin = $this->safeNumeric(Arr::get($json, 'domain.min'), 0.0);
        $domainMax = $this->safeNumeric(Arr::get($json, 'domain.max'), 1.0);
        $score10   = $this->score01To10($this->normalize01($closest['value'], $domainMin, $domainMax));

        $one = [
            'product' => $p,
            'succeed' => true,
            'status'  => 200,
            'units'   => Arr::get($json, 'units', null),
            'value'   => ['raw'=>$closest['value'], 'units'=>Arr::get($json, 'units', null)],
            'score'   => [
                'raw'      => $closest['value'],
                'score_10' => $score10,
                'domain'   => ['min'=>$domainMin,'max'=>$domainMax],
                'method'   => 'linear_01_on_server_domain',
            ],
            'place' => [
                'lat'=>$closest['lat'],'lon'=>$closest['lon'],
                'distance_km'=>$distKm,
                'distance_note'=>'distance from requested point to nearest grid cell center',
            ],
            'meta' => [
                'z'=>Arr::get($json,'z',$zEff),
                't'=>Arr::get($json,'t',$tCanonical),
                'grid_deg'=>Arr::get($json,'grid_deg',0.1),
                'bucket_deg'=>Arr::get($json,'bucket_deg',0.1),
                'palette'=>Arr::get($json,'palette',null),
                'mode'=>Arr::get($json,'mode','future'),
                'score_domain_strategy'=>Arr::get($json,'domain.strategy'),
            ],
        ];

        if ($debug) {
            $one['debug'] = [
                'internal_http' => [
                    'url'   => $fgUrl,
                    'query' => $requests[$p],
                    'status'=> $resp->status(),
                ],
                'cells_count' => count($cells),
            ];
        }

        $perProduct[$p] = $one;
        $perProductScore10[$p] = $score10;
        $anyOk = true;
    }

    return [$perProduct, $perProductScore10, $anyOk, $anyFail];
}


    // -------------------------- Parsers & helpers --------------------------

    private function parsePoint(Request $request): array
    {
        $lat = $request->query('lat', null);
        $lon = $request->query('lon', null);
        if (!is_numeric($lat) || !is_numeric($lon)) {
            throw new \InvalidArgumentException("lat/lon are required");
        }
        $lat = floatval($lat);
        $lon = floatval($lon);
        if ($lat < -90 || $lat > 90 || $lon < -180 || $lon > 180) {
            throw new \InvalidArgumentException("lat/lon out of range");
        }
        if (!$this->inNorthAmerica($lat, $lon)) {
            throw new \InvalidArgumentException("point out of domain (North America only)");
        }
        return [$lat, $lon];
    }

    private function parseProducts(Request $request): array
    {
        $raw = $request->query('products', 'no2,hcho,o3tot');
        $parts = array_filter(array_map('trim', explode(',', $raw)));
        $valid = ['no2','hcho','o3tot','cldo4'];
        $res = [];
        foreach ($parts as $p) {
            $p = strtolower($p);
            if (in_array($p, $valid, true)) $res[] = $p;
        }
        if (empty($res)) $res = ['no2','hcho','o3tot'];
        return array_values(array_unique($res));
    }

    // Accepts t=+6 | 6 | +6h | 6h | t_hours=6 → returns numeric 0..12
    private function parseTHours(Request $request): int
    {
        $raw = $request->query('t_hours', null);
        if ($raw === null) $raw = $request->query('t', null);
        if ($raw === null) {
            throw new \InvalidArgumentException("t must be like +0..+12");
        }

        $raw = trim((string)$raw);
        if (!preg_match('/^\s*\+?\s*(\d{1,2})\s*(h)?\s*$/i', $raw, $m)) {
            throw new \InvalidArgumentException("t must be like +0..+12");
        }
        $h = intval($m[1]);
        if ($h < 0 || $h > 12) {
            throw new \InvalidArgumentException("t must be like +0..+12");
        }
        return $h;
    }

    private function clampZEff($z): int
    {
        $z = intval($z);
        if ($z < 9) return 9;      // 8 => 9
        if ($z > 11) return 11;    // >=12 => 11
        return $z;                 // 9..11
    }

    /**
     * Builds a small bbox around the point.
     * Default pad ~0.35° (~39km at mid-latitudes) unless radius_km is provided (1..100 km).
     * Returns [W,S,E,N].
     */
    private function buildbboxAroundPoint(float $lat, float $lon, Request $request): array
    {
        $radiusKm = $request->query('radius_km', null);
        if ($radiusKm !== null && is_numeric($radiusKm)) {
            $r = max(1.0, min(100.0, floatval($radiusKm))); // 1..100 km
            $dLat = $r / 111.0;
            $dLon = $r / (111.0 * max(0.1, cos(deg2rad($lat))));
            return [$lon - $dLon, $lat - $dLat, $lon + $dLon, $lat + $dLat];
        }
        $pad = 0.35; // degrees (matches grid_deg≈0.1)
        return [$lon - $pad, $lat - $pad, $lon + $pad, $lat + $pad];
    }

    /** Clamp bbox to a fixed North America domain (W=-170,E=-50,S=15,N=75) */
    private function clampBboxToNA(array $bbox): array
    {
        [$w,$s,$e,$n] = $bbox;
        $W=-170.0; $E=-50.0; $S=15.0; $N=75.0;
        $w = max($W, min($E, $w));
        $e = max($W, min($E, $e));
        $s = max($S, min($N, $s));
        $n = max($S, min($N, $n));
        // ensure ordering
        if ($e < $w) [$w,$e] = [$e,$w];
        if ($n < $s) [$s,$n] = [$n,$s];
        return [$w,$s,$e,$n];
    }

    private function parseWeights(Request $request, array $products): array
    {
        $w = $request->query('weights', []);
        if (!is_array($w)) $w = [];

        $defaults = [
            'no2'   => 0.5,
            'hcho'  => 0.25,
            'o3tot' => 0.25,
            'cldo4' => 0.0,
        ];

        $res = [];
        foreach ($products as $p) {
            $res[$p] = isset($w[$p]) && is_numeric($w[$p]) ? floatval($w[$p]) : ($defaults[$p] ?? 0.0);
        }

        // Normalize
        $sum = array_sum($res);
        if ($sum <= 0) {
            $eq = 1.0 / max(1, count($res));
            foreach ($res as $k => $_) $res[$k] = $eq;
            return $res;
        }
        foreach ($res as $k => $v) $res[$k] = $v / $sum;
        return $res;
    }

    private function toBool($v): bool
    {
        if (is_bool($v)) return $v;
        $s = strtolower(trim((string)$v));
        return in_array($s, ['1','true','yes','y','on'], true);
    }

    private function inNorthAmerica(float $lat, float $lon): bool
    {
        $south = 15.0;  $north = 75.0;  $west = -170.0;  $east = -50.0;
        return ($lat >= $south && $lat <= $north && $lon >= $west && $lon <= $east);
    }

    // -------------------------- Single-product helpers (kept for structure parity) --------------------------

    /**
     * NOTE: kept for debugging / parity. Not used in normal flow anymore,
     * because we use assessProductsFutureConcurrent() with Http::pool().
     */
    private function assessOneProductFuture(string $product, float $lat, float $lon, int $zEff, string $tCanonical, array $bbox, bool $debug): array
    {
        // Internal sub-request (fast but sequential). Left here for reference.
        $sub = Request::create(
            uri: '/api/v1/frontend/air-quality/forecast-grids',
            method: 'GET',
            parameters: [
                'product'       => $product,
                'z'             => $zEff,
                't'             => $tCanonical, // "+H"
                'bbox'          => implode(',', $bbox),
                'format'        => 'json',
                'stations'      => ($product === 'no2') ? 1 : 0,
                'stations_debug'=> $debug ? 1 : 0,
                'meteo'         => 1,
                'meteo_debug'   => $debug ? 1 : 0,
            ]
        );

        $svc = new ForecastGrids();
        $resp = $svc->build($sub);

        $json = json_decode($resp->getContent(), true);
        if (!is_array($json) || empty($json) || Arr::get($json, 'succeed') !== true) {
            return [
                'product' => $product,
                'succeed' => false,
                'status'  => Arr::get($json, 'status', 502),
                'message' => Arr::get($json, 'message', 'no data'),
            ];
        }

        $cells = Arr::get($json, 'cells', []);
        $meta  = Arr::only($json, ['product','units','mode','z','t','grid_deg','bucket_deg','domain','bbox','bbox_effective','palette']);
        if (empty($cells)) {
            return [
                'product' => $product,
                'succeed' => false,
                'status'  => 204,
                'message' => 'no cells',
                'meta'    => $meta,
            ];
        }

        [$closest, $distKm] = $this->nearestCell($lat, $lon, $cells);

        $domainMin = $this->safeNumeric(Arr::get($json, 'domain.min'), 0.0);
        $domainMax = $this->safeNumeric(Arr::get($json, 'domain.max'), 1.0);
        $score10   = $this->score01To10($this->normalize01($closest['value'], $domainMin, $domainMax));

        $out = [
            'product' => $product,
            'succeed' => true,
            'status'  => 200,
            'units'   => Arr::get($json, 'units', null),
            'value'   => [
                'raw'   => $closest['value'],
                'units' => Arr::get($json, 'units', null),
            ],
            'score'   => [
                'raw'       => $closest['value'],
                'score_10'  => $score10,
                'domain'    => ['min' => $domainMin, 'max' => $domainMax],
                'method'    => 'linear_01_on_server_domain',
            ],
            'place' => [
                'lat'     => $closest['lat'],
                'lon'     => $closest['lon'],
                'distance_km' => $distKm,
                'distance_note' => 'distance from requested point to nearest grid cell center',
            ],
            'meta' => [
                'z'          => Arr::get($json, 'z', $zEff),
                't'          => Arr::get($json, 't', $tCanonical),
                'grid_deg'   => Arr::get($json, 'grid_deg', 0.1),
                'bucket_deg' => Arr::get($json, 'bucket_deg', 0.1),
                'palette'    => Arr::get($json, 'palette', null),
                'mode'       => Arr::get($json, 'mode', 'future'),
                'score_domain_strategy' => Arr::get($json, 'domain.strategy'),
            ],
        ];

        if ($debug) {
            $out['debug'] = [
                'internal_call' => [
                    'path'   => '/api/v1/frontend/air-quality/forecast-grids',
                    'query'  => [
                        'product' => $product,
                        'z'       => $zEff,
                        't'       => $tCanonical,
                        'bbox'    => implode(',', $bbox),
                        'format'  => 'json',
                        'stations'=> ($product === 'no2') ? 1 : 0,
                        'meteo'   => 1,
                    ],
                ],
                'cells_count' => count($cells),
            ];
        }

        return $out;
    }

    private function nearestCell(float $lat, float $lon, array $cells): array
    {
        $best = null;
        $bestD = PHP_FLOAT_MAX;

        foreach ($cells as $c) {
            if (!isset($c['lat'], $c['lon'], $c['value'])) continue;
            $d = $this->haversineKm($lat, $lon, floatval($c['lat']), floatval($c['lon']));
            if ($d < $bestD) {
                $bestD = $d;
                $best = $c;
            }
        }
        if ($best === null) {
            $best = $cells[0];
            $bestD = $this->haversineKm($lat, $lon, floatval($best['lat']), floatval($best['lon']));
        }
        return [$best, $bestD];
    }

    private function haversineKm($lat1, $lon1, $lat2, $lon2): float
    {
        $R = 6371.0; // km
        $dLat = deg2rad($lat2 - $lat1);
        $dLon = deg2rad($lon2 - $lon1);
        $a = sin($dLat/2) * sin($dLat/2)
           + cos(deg2rad($lat1)) * cos(deg2rad($lat2))
           * sin($dLon/2) * sin($dLon/2);
        $c = 2 * atan2(sqrt($a), sqrt(1-$a));
        return $R * $c;
    }

    private function normalize01(float $v, float $min, float $max): float
    {
        if ($max <= $min) return 0.0;
        $nv = ($v - $min) / ($max - $min);
        return max(0.0, min(1.0, $nv));
    }

    private function score01To10(float $nv): float
    {
        return round(1.0 + 9.0 * $nv, 1); // 0..1 → 1..10
    }

    private function safeNumeric($v, $default): float
    {
        return is_numeric($v) ? floatval($v) : $default;
    }

    private function buildOverallScores(array $perProductScore10, array $weights): array
    {
        $sumW = 0.0;
        $acc  = 0.0;
        foreach ($perProductScore10 as $p => $score10) {
            if (!is_numeric($score10)) continue;
            $w = $weights[$p] ?? 0.0;
            $acc  += $w * (float)$score10;
            $sumW += $w;
        }
        if ($sumW <= 0.0) {
            return [
                'succeed' => false,
                'status'  => 204,
                'message' => 'overall cannot be computed (no valid product scores)',
                'weights' => $weights,
            ];
        }

        $score10  = round($acc / $sumW, 1);
        $score100 = round($score10 * 10.0, 0);

        return [
            'succeed'   => true,
            'status'    => 200,
            'score_10'  => $score10,
            'score_100' => $score100,
            'weights'   => $weights,
            'recommended_actions' => $this->recommendByScore10($score10),
        ];
    }

    /** Compute disease risks using per-product score_10s into 0..100 scale */
    private function buildHealthSection(array $prodScore10, array $activeProducts): array
    {
        $risks = [];
        foreach ($this->DISEASE_WEIGHTS as $dis) {
            $acc = 0.0; $wacc = 0.0; $contributors = [];
            foreach ($dis['weights'] as $p=>$w) {
                if (!in_array($p, $activeProducts, true)) continue;   // only active products
                $s10 = $prodScore10[$p] ?? null;
                $contributors[] = ['product'=>$p,'weight'=>$w,'score10'=>$s10];
                if (!is_numeric($s10)) continue;
                $acc  += $w * ($s10 * 10.0); // 0..100 scale
                $wacc += $w;
            }
            $risk100 = $wacc > 0 ? intval(round($acc / $wacc)) : 0;
            $level = $risk100 >= 80 ? 'Very High' : ($risk100 >= 60 ? 'High' : ($risk100 >= 40 ? 'Moderate' : ($risk100 >= 20 ? 'Low' : 'Very Low')));

            $risks[] = [
                'id'      => $dis['id'],
                'name'    => $dis['title'],
                'risk_0_100' => $risk100,
                'level'   => $level,
                'note'    => $dis['note'],
                'contributors' => $contributors,
            ];
        }
        usort($risks, fn($a,$b)=>$b['risk_0_100'] <=> $a['risk_0_100']);

        return [
            'succeed'=>true,
            'status'=>200,
            'risks'=>$risks,
            'explain'=>'Disease risk is a heuristic mix of product-specific normalized scores and disease sensitivity weights.',
        ];
    }

    /**
 * Map a 1..10 score to a user-facing level + short advice.
 */
private function recommendByScore10(float $s10): array
{
    if ($s10 >= 8.5) {
        return [
            'level'  => 'Very High',
            'advice' => 'Limit outdoor activities; consider a well-fitted mask for sensitive groups.'
        ];
    }
    if ($s10 >= 6.5) {
        return [
            'level'  => 'High',
            'advice' => 'Reduce prolonged outdoor exertion; keep rescue meds handy for asthma/COPD.'
        ];
    }
    if ($s10 >= 4.0) {
        return [
            'level'  => 'Moderate',
            'advice' => 'Generally okay; sensitive groups should monitor symptoms and take breaks.'
        ];
    }
    return [
        'level'  => 'Low',
        'advice' => 'Conditions are favorable for normal outdoor activities.'
    ];
}

}
