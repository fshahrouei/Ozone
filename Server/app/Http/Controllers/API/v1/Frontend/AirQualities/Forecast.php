<?php
/**
 * Forecast Controller
 *
 * This controller builds a forecast surface (PNG or JSON metadata) for TEMPO-based products
 * (NO2, HCHO, total O3, cloud fraction proxy cldO4), with optional:
 *   - Hour-of-day (HOD) ratio extrapolation for t=+1..+12 hours
 *   - Meteorology-based multiplicative adjustments (10m wind, BLH)
 *   - Observation stations fusion (IDW over grid) for NO2
 *
 * Notes:
 * - The implementation is read-only; it uses files in storage_path("app/...") as inputs.
 * - PNG output is a simple nearest-neighbor "bin fill" of the HxW grid to the target tile size.
 * - JSON output returns metadata (domain, stats, headers); the raw matrix is JSON-sanitized but
 *   currently commented out in the response to reduce payload size (see '// NEW' markers).
 * - All non-finite values (NaN/Inf) are kept internally and skipped in rendering; JSON branch
 *   converts them to `null` in case you want to include 'data'.
 */

namespace App\Http\Controllers\API\V1\Frontend\AirQualities;

use Illuminate\Http\Request;

class Forecast
{
    /** Supported TEMPO products */
    private const PRODUCTS = ['no2','hcho','o3tot','cldo4'];

    /** Allowed zoom range for output PNG tile sizes */
    private const Z_MIN = 3;
    private const Z_MAX = 8;

    /** Hour-Of-Day (HOD) ratio clamps + numerical epsilon for safety */
    private const HOD_RATIO_MIN = 0.33;
    private const HOD_RATIO_MAX = 3.0;
    private const EPS            = 1e-9;

    /** Keep last loaded stations for debug overlay (white dots) */
    private $lastLoadedStationsForDebug = null;

    /**
     * Main entrypoint: builds a forecast PNG or JSON summary depending on 'format' or 'Accept'.
     * Query params (subset):
     *  - product=no2|hcho|o3tot|cldo4
     *  - z=3..8
     *  - t=0..12 (0 = nowcast/base field; >0 = HOD-based extrapolation)
     *  - format=png|json (or content negotiation via Accept)
     *  - palette=viridis|gray
     *  - domain=auto|fixed:min,max
     *  - nocache=1 (bypass PNG cache)
     *  - stations=1 + stations_* knobs (NO2 only)
     *  - meteo=1 + meteo_* knobs (wind, BLH factors)
     */
    public function build(Request $request)
    {
        try {
            /* ---------- 1) Params ---------- */
            $product = strtolower((string)$request->query('product', 'no2'));
            if (!in_array($product, self::PRODUCTS, true)) {
                return response()->json(['succeed'=>false,'status'=>422,'message'=>'invalid product'], 422);
            }

            $z = (int)$request->query('z', 6);
            if ($z < self::Z_MIN || $z > self::Z_MAX) {
                return response()->json(['succeed'=>false,'status'=>422,'message'=>'invalid z (3..8)'], 422);
            }

            $paletteParam = strtolower((string)$request->query('palette', ''));
            $domainParam  = (string)$request->query('domain', 'auto');
            $tStr         = (string)$request->query('t', '0');
            $nocache      = (string)$request->query('nocache', '0');

            // Format: `png` or `json` (default via Accept negotiation: JSON if Accept includes application/json)
            $format       = strtolower((string)$request->query('format', ''));
            if ($format === '') {
                $accept = strtolower((string)($_SERVER['HTTP_ACCEPT'] ?? ''));
                $format = (strpos($accept, 'application/json') !== false) ? 'json' : 'png';
            }
            if (!in_array($format, ['png','json'], true)) $format = 'json';

            // Stations fusion parameters (only used for NO2 if enabled)
            $useStations       = (int)$request->query('stations', 0) === 1;
            $stationsDebug     = (int)$request->query('stations_debug', 0) === 1;
            $stMaxAgeH         = (float)$request->query('stations_max_age_h', 3.0);
            $stRadiusKm        = (float)$request->query('stations_radius_km', 75.0);
            $stPow             = (float)$request->query('stations_pow', 2.0);
            $stWMax            = (float)$request->query('stations_w_max', 0.60);
            $stAutoScale       = (int)$request->query('stations_autoscale', 1) === 1;
            $stForce           = (int)$request->query('stations_force', 0) === 1;

            // Meteorology adjustment parameters (Stage-3 tuning)
            $useMeteo      = (int)$request->query('meteo', 0) === 1;
            $meteoDebug    = (int)$request->query('meteo_debug', 0) === 1; // currently informational
            $betaW         = (float)$request->query('meteo_beta_w',  -0.08);  // wind sensitivity
            $WS0           = (float)$request->query('meteo_ws0',      3.0);   // reference wind speed (m/s)
            $betaBLH       = (float)$request->query('meteo_beta_blh', -0.25); // BLH sensitivity
            $BLH0          = (float)$request->query('meteo_blh0',     800.0); // reference BLH (m)
            $fmin          = (float)$request->query('meteo_fmin',     0.60);  // overall factor clamp min
            $fmax          = (float)$request->query('meteo_fmax',     1.60);  // overall factor clamp max

            // Hour offset parsing: accepts "+3" or "3"
            $t = ($tStr !== '' && $tStr[0] === '+') ? (int)substr($tStr, 1) : (int)$tStr;
            if ($t < 0 || $t > 12) {
                return response()->json(['succeed'=>false,'status'=>422,'message'=>'t must be 0..12'], 422);
            }

            /* ---------- 2) TEMPO paths ---------- */
            $rootTempo  = storage_path("app/tempo/{$product}");
            $fcDir      = "{$rootTempo}/fc_support";
            $latestPath = "{$fcDir}/latest.json";
            $hodDir     = "{$fcDir}/hod";
            $hodMeta    = "{$hodDir}/meta.json";

            if (!is_file($latestPath) && !is_file($latestPath . '.gz')) {
                return response()->json(['succeed'=>false,'status'=>503,'message'=>'missing latest.json (run summaries first)'], 503);
            }
            if (!is_dir($hodDir)) {
                return response()->json(['succeed'=>false,'status'=>503,'message'=>'missing hod/ (run summaries first)'], 503);
            }

            /* ---------- 3) Read latest.json ---------- */
            $latest = $this->readJsonRobust($latestPath);
            if (!is_array($latest)) {
                return response()->json(['succeed'=>false,'status'=>500,'message'=>'latest.json invalid','detail'=>$latest], 500);
            }

            $shape = $latest['shape'] ?? null;     // [H,W]
            $bbox  = $latest['bbox']  ?? null;     // [S,N,W,E]
            $grid  = $latest['grid_deg'] ?? 0.1;
            if (!is_array($shape) || count($shape)!==2 || !is_array($bbox) || count($bbox)!==4) {
                return response()->json(['succeed'=>false,'status'=>500,'message'=>'latest.json missing shape/bbox'], 500);
            }

            $V    = $latest['data']['value'] ?? null;   // HxW base values
            $AGE  = $latest['data']['age_h'] ?? null;   // HxW age in hours since observation
            if (!is_array($V) || !is_array($AGE)) {
                return response()->json(['succeed'=>false,'status'=>500,'message'=>'latest.json missing data.value/age_h'], 500);
            }

            $H = (int)$shape[0]; $W = (int)$shape[1];
            if ($H <= 0 || $W <= 0) {
                return response()->json(['succeed'=>false,'status'=>500,'message'=>'invalid shape'], 500);
            }

            // Precompute longitude axis for local-hour conversion (HOD)
            $Wdeg = (float)$bbox[2];
            $Edeg = (float)$bbox[3];
            $lon1d = [];
            $step  = ($W === 1) ? 0.0 : ($Edeg - $Wdeg) / ($W - 1);
            for ($x=0; $x<$W; $x++) $lon1d[$x] = $Wdeg + $step*$x;

            /* ---------- 4) Load HOD slices (0..23) ---------- */
            $HOD = [];
            for ($h=0; $h<24; $h++) {
                $slice = $this->readJsonSimple(sprintf("%s/hour_%02d.json", $hodDir, $h));
                $HOD[$h] = is_array($slice) ? ($slice['data'] ?? null) : null;
            }
            $hodMetaJs = $this->readJsonSimple($hodMeta);
            $newestGid = is_array($hodMetaJs) ? ($hodMetaJs['newest_gid'] ?? null) : null;

            /* ---------- 5) Product spec & palette ---------- */
            $spec = $this->productSpec($product);
            $cap  = (float)$spec['cap'];
            $allowZero = (bool)$spec['allowZero'];
            $defaultPalette = $spec['palette'] ?? 'viridis';
            $paletteName = $paletteParam !== '' ? $paletteParam : $defaultPalette;
            if ($paletteName !== 'gray' && $paletteName !== 'viridis') $paletteName = $defaultPalette;
            $unit = $latest['unit'] ?? ($spec['units'] ?? '');

            /* ---------- 6) Build base forecast grid F (HxW) ---------- */
            $F = $this->allocFloat2D($H, $W);

            if ($t === 0) {
                // Nowcast: clamp raw values into [0, cap], reject invalid/non-positive if allowZero=false
                for ($y=0; $y<$H; $y++) {
                    for ($x=0; $x<$W; $x++) {
                        $v = $this->toFloat($V[$y][$x]);
                        if (!is_finite($v) || (!$allowZero && $v <= 0.0)) { $F[$y][$x] = NAN; continue; }
                        $F[$y][$x] = max(0.0, min($cap, $v));
                    }
                }
            } else {
                // HOD forecast: v * clamp(HOD_t / HOD_l, [0.33, 3.0]) using local time by longitude
                for ($y=0; $y<$H; $y++) {
                    for ($x=0; $x<$W; $x++) {
                        $v = $this->toFloat($V[$y][$x]);
                        $ageH = $this->toFloat($AGE[$y][$x]);
                        if (!is_finite($v) || (!$allowZero && $v <= 0.0)) { $F[$y][$x] = NAN; continue; }

                        // Derive last local hour from last observation time + longitude offset
                        $lastObsUtc = is_finite($ageH) ? (time() - (int)round($ageH * 3600.0)) : time();
                        $lon = (float)$lon1d[$x];
                        $offsetSec     = ($lon / 360.0) * 86400.0;
                        $lastLocalHour = (int)floor( (($lastObsUtc + $offsetSec) / 3600.0) ) % 24;
                        if ($lastLocalHour < 0) $lastLocalHour += 24;
                        $targetLocalHour = ($lastLocalHour + $t) % 24;

                        $HODl = $this->hodAt($HOD, $lastLocalHour,  $y, $x);
                        $HODt = $this->hodAt($HOD, $targetLocalHour, $y, $x);

                        $fv = $v;
                        if (is_finite($HODl) && $HODl > self::EPS && is_finite($HODt)) {
                            $ratio = $HODt / max(self::EPS, $HODl);
                            if ($ratio < self::HOD_RATIO_MIN) $ratio = self::HOD_RATIO_MIN;
                            if ($ratio > self::HOD_RATIO_MAX) $ratio = self::HOD_RATIO_MAX;
                            $fv = $v * $ratio;
                        }

                        if (!is_finite($fv) || (!$allowZero && $fv <= 0.0)) { $F[$y][$x] = NAN; continue; }
                        $F[$y][$x] = max(0.0, min($cap, $fv));
                    }
                }
            }

            /* ---------- 6.2) Optional meteorology adjustments (wind + BLH) ---------- */
            $meteoInfo = [
                'applied' => false,
                'why'     => 'off',
                'run'     => 'na',
                'fields'  => 'na',
                'factor_min' => 'na',
                'factor_max' => 'na',
                'factor_mean'=> 'na',
                'factor_blh_min'  => 'na',
                'factor_blh_max'  => 'na',
                'factor_blh_mean' => 'na',
                'WS0'     => $WS0, 'betaW'=>$betaW,
                'BLH0'    => $BLH0, 'betaBLH'=>$betaBLH,
                'fmin'    => $fmin, 'fmax'=>$fmax,
            ];

            if ($useMeteo) {
                $M = $this->loadMeteoForHour($t);
                if (!is_array($M)) {
                    $meteoInfo['why'] = 'no_index';
                } else {
                    if (!$this->shapeAndBoxMatch($M, $shape, $bbox)) {
                        $meteoInfo['why'] = 'shape_bbox_mismatch';
                    } else {
                        $fields = [];
                        $appliedSomething = false;

                        // Wind factor from u10/v10 -> ws, multiplicative clamp
                        if (isset($M['u10']) && isset($M['v10'])) {
                            $applyW = $this->applyMeteoWindFactor(
                                $F, $M['u10'], $M['v10'], $H, $W,
                                $betaW, $WS0, $fmin, $fmax, $cap, $allowZero
                            );
                            if ($applyW['applied'] ?? false) {
                                $appliedSomething = true;
                                $fields[] = 'u10'; $fields[] = 'v10';
                                $meteoInfo['factor_min']  = sprintf('%.3f',$applyW['fmin']);
                                $meteoInfo['factor_max']  = sprintf('%.3f',$applyW['fmax']);
                                $meteoInfo['factor_mean'] = sprintf('%.3f',$applyW['fmean']);
                            }
                        }

                        // BLH factor, multiplicative clamp
                        if (isset($M['blh'])) {
                            $applyB = $this->applyMeteoBLHFactor(
                                $F, $M['blh'], $H, $W,
                                $betaBLH, $BLH0, $fmin, $fmax, $cap, $allowZero
                            );
                            if ($applyB['applied'] ?? false) {
                                $appliedSomething = true;
                                $fields[] = 'blh';
                                $meteoInfo['factor_blh_min']  = sprintf('%.3f',$applyB['fmin']);
                                $meteoInfo['factor_blh_max']  = sprintf('%.3f',$applyB['fmax']);
                                $meteoInfo['factor_blh_mean'] = sprintf('%.3f',$applyB['fmean']);
                            }
                        }

                        $meteoInfo['applied'] = $appliedSomething;
                        $meteoInfo['why']     = $appliedSomething ? 'ok' : 'no_valid_field';
                        $meteoInfo['fields']  = empty($fields) ? 'na' : implode(',', array_values(array_unique($fields)));
                        $meteoInfo['run']     = $M['run'] ?? 'na';
                    }
                }
            }

            /* ---------- 6.5) Optional stations fusion (NO2 only) ---------- */
            $stationsUsed = false;
            $stationsCnt  = 0;
            $stationsMeanAge = null;
            $gridCoverPct = 0.0;
            $stUnitHdr = 'na';
            $stUnitMismatch = false;
            $stSourceTs = 'na';
            $stWhy = 'off';
            $stSrcPath = 'na';
            $stAutoScaleK = null;

            $canUseStations = $useStations && ($product === 'no2');
            if ($canUseStations) {
                $paramHint = ($product === 'o3tot') ? 'o3' : $product;
                $st = $this->loadStationsForProduct($product, $paramHint, $stMaxAgeH, $stForce);

                $stWhy     = $st['why'] ?? 'ok';
                $stSrcPath = $st['src'] ?? 'na';
                $stSourceTs= $st['ts']  ?? 'na';

                if (!empty($st['points'])) {
                    // Units sanity check: molecule columns vs molecule columns (simple heuristic)
                    $rawUnit = $st['unit'] ?? '';
                    $stUnitHdr = $rawUnit ? strtolower($rawUnit) : 'na';

                    $isSameUnit = (strpos(strtolower($unit),'molec') !== false) && (strpos($stUnitHdr,'molec') !== false);
                    $stUnitMismatch = !$isSameUnit;

                    // Normalize points: filter by age, positivity, etc.
                    $pts = [];
                    $ageSum = 0.0;
                    foreach ($st['points'] as $p) {
                        $lat = isset($p['lat']) ? (float)$p['lat'] : NAN;
                        $lon = isset($p['lon']) ? (float)$p['lon'] : NAN;
                        $val = isset($p['val']) ? (float)$p['val'] : (isset($p['value'])?(float)$p['value']:NAN);
                        $age = isset($p['age_h']) ? (float)$p['age_h'] : NAN;
                        if (!is_finite($lat) || !is_finite($lon) || !is_finite($val) || !is_finite($age)) continue;
                        if ($age > $stMaxAgeH && !$stForce) continue;
                        if (!$allowZero && $val <= 0.0) continue;
                        $pts[] = ['lat'=>$lat,'lon'=>$lon,'val'=>$val,'age_h'=>$age];
                        $ageSum += $age;
                    }

                    // Optional auto-scale if units differ but patterns align; use median F/p ratio
                    if (!$isSameUnit && $stAutoScale && !empty($pts)) {
                        $ratios = [];
                        foreach ($pts as $p) {
                            $gx = $this->lonToGridX($p['lon'], $bbox, $W);
                            $gy = $this->latToGridY($p['lat'], $bbox, $H);
                            if ($gx<0||$gx>=$W||$gy<0||$gy>=$H) continue;
                            $f = $F[$gy][$gx];
                            if (!is_finite($f)) continue;
                            if ($p['val'] > self::EPS) $ratios[] = $f / $p['val'];
                        }
                        if (!empty($ratios)) {
                            sort($ratios);
                            $stAutoScaleK = $ratios[(int)floor(0.5*(count($ratios)-1))];
                            $stAutoScaleK = max(1e-9, min(1e18, $stAutoScaleK));
                            foreach ($pts as &$q) { $q['val'] = min($cap, max(0.0, $q['val'] * $stAutoScaleK)); }
                            unset($q);
                            $stUnitMismatch = false;
                            $isSameUnit = true;
                        } elseif ($stForce) {
                            // If force=1, accept values as-is (still clamped)
                            foreach ($pts as &$q) { $q['val'] = min($cap, max(0.0, $q['val'])); } unset($q);
                        }
                    }

                    $stationsCnt = count($pts);
                    if ($stationsCnt > 0) $stationsMeanAge = $ageSum / $stationsCnt;

                    // Blend gridded F with station IDW only if coverage and unit sanity allow it (or forced)
                    if ($stationsCnt > 0 && (!$stUnitMismatch || $stForce)) {
                        [$G, $Cov] = $this->idwGrid($pts, $bbox, $shape, $stRadiusKm, $stPow, $allowZero, $cap);
                        $covCnt=0; $tot=$H*$W; for($y2=0;$y2<$H;$y2++) for($x2=0;$x2<$W;$x2++) if($Cov[$y2][$x2]>0) $covCnt++;
                        $gridCoverPct = ($tot>0)? (100.0*$covCnt/$tot) : 0.0;

                        // Weight by freshness: max at age=0, -> 0 at age>=stMaxAgeH
                        $freshFactor = ($stMaxAgeH>0 && $stationsMeanAge!==null)
                            ? max(0.0, min(1.0, 1.0 - ($stationsMeanAge/$stMaxAgeH))) : 0.0;
                        $w = $stWMax * $freshFactor;

                        // Local coverage modulates weight (more coverage => higher contribution)
                        for ($yy=0; $yy<$H; $yy++) {
                            for ($xx=0; $xx<$W; $xx++) {
                                $g = $G[$yy][$xx];
                                if (!is_finite($g) || $Cov[$yy][$xx] <= 0) continue;
                                $f = $F[$yy][$xx];
                                if (!is_finite($f)) { $F[$yy][$xx] = $g; continue; }
                                $localW = $w * max(0.25, min(1.0, $Cov[$yy][$xx] / 3.0));
                                $F[$yy][$xx] = $localW * $g + (1.0 - $localW) * $f;
                            }
                        }
                        $stationsUsed = ($w > 0.0) && ($gridCoverPct > 0.0);
                        $stWhy = $stationsUsed ? 'used' : 'weight_zero';
                    } else {
                        if ($stWhy==='ok') $stWhy = $stationsCnt===0 ? 'empty_data' : 'unit_mismatch';
                    }
                }
            }

            /* ---------- 7) Domain selection (color mapping range) ---------- */
            if (stripos($domainParam, 'fixed:') === 0) {
                // fixed:min,max
                $specDom = substr($domainParam, 6);
                $parts = explode(',', $specDom);
                if (count($parts) !== 2) {
                    return response()->json(['succeed'=>false,'status'=>422,'message'=>'invalid domain format'], 422);
                }
                $vmin = max(0.0, min($cap, (float)$parts[0]));
                $vmax = max($vmin + self::EPS, min($cap, (float)$parts[1]));
                $domKey = sprintf('fixed:%.6g,%.6g', $vmin, $vmax);
            } else {
                // Auto domain from quantiles with safety span
                [$vmin, $vmax] = $this->estimateDomainAuto($F, (float)$spec['cap'], $spec['qLow'], $spec['qHigh'], (bool)$spec['allowZero']);
                $domKey = 'auto';
            }

            /* ---------- 8) Cache path naming (includes meteo+stations hashes) ---------- */
            $palKey  = $paletteName;
            $gidKey  = $newestGid ? $newestGid : 'na';
            $cacheDir= "{$rootTempo}/tiles_fc/z{$z}";
            @mkdir($cacheDir, 0775, true);

            $stHash = 'st:0';
            if ($canUseStations) {
                $raw = json_encode([
                    'use'=>true,'maxAgeH'=>$stMaxAgeH,'rKm'=>$stRadiusKm,'pow'=>$stPow,'wMax'=>$stWMax,
                    'auto'=>$stAutoScale,'force'=>$stForce
                ], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
                $stHash = 'st:' . substr(md5($raw), 0, 8);
            }

            $metHash = 'met:off';
            if ($useMeteo) {
                $rawM = json_encode([
                    'betaW'=>$betaW,'WS0'=>$WS0,'betaBLH'=>$betaBLH,'BLH0'=>$BLH0,'fmin'=>$fmin,'fmax'=>$fmax
                ], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
                $metHash = 'met:' . substr(md5($rawM), 0, 8);
            }

            $pngName = sprintf(
                "%s__FC__t:+%dh__base:%s__z%d__pal:%s__dom:%s__%s__%s.png",
                $product, $t, $gidKey, $z, $palKey, str_replace([':',','],['-','_'],$domKey), $stHash, $metHash
            );
            $pngPath = "{$cacheDir}/{$pngName}";

            // Serve cached PNG if allowed and available
            if ($format === 'png' && $nocache !== '1') {
                $respCached = $this->serveCachedPng($request, $pngPath);
                if ($respCached !== null) return $respCached;
            }

            /* ---------- 9) Response headers & stats ---------- */
            [$validCnt,$totCnt] = $this->countFinite($F);
            $st = $this->statsSummary($F, $cap, $allowZero);

            $headers = [
                'Cache-Control'       => 'public, max-age=600',
                'X-Forecast-Mode'     => $canUseStations ? 'fusion-stations' : 'tempo-only',
                'X-Forecast-Source'   => $canUseStations ? 'tempo+stations' : 'tempo',
                'X-Forecast-Proxy'    => $canUseStations ? 'stations-idw' : 'none',
                'X-Forecast-T'        => "+{$t}h",
                'X-Grid-Deg'          => (string)$grid,
                'X-Units'             => (string)$unit,
                'X-Valid-Ratio'       => ($totCnt>0 ? sprintf('%.1f%%', 100.0*$validCnt/$totCnt) : '0%'),
                'X-Stats-Count'       => (string)$st['count'],
                'X-Stats-Uniq'        => (string)$st['uniq'],
                'X-Stats-Min'         => is_null($st['min']) ? 'na' : sprintf('%.6g',$st['min']),
                'X-Stats-P10'         => is_null($st['p10']) ? 'na' : sprintf('%.6g',$st['p10']),
                'X-Stats-P50'         => is_null($st['p50']) ? 'na' : sprintf('%.6g',$st['p50']),
                'X-Stats-P90'         => is_null($st['p90']) ? 'na' : sprintf('%.6g',$st['p90']),
                'X-Stats-Max'         => is_null($st['max']) ? 'na' : sprintf('%.6g',$st['max']),
                // Stations debug
                'X-Stations-Used'        => $canUseStations && $stationsUsed ? '1' : '0',
                'X-Stations-Count'       => (string)$stationsCnt,
                'X-Stations-MeanAgeH'    => is_null($stationsMeanAge) ? 'na' : sprintf('%.2f', $stationsMeanAge),
                'X-Stations-GridCover'   => sprintf('%.1f%%', $gridCoverPct),
                'X-Stations-Unit'        => $stUnitHdr,
                'X-Stations-UnitMismatch'=> $stUnitMismatch ? '1' : '0',
                'X-Stations-SourceTs'    => $stSourceTs,
                'X-Stations-Why'         => $stWhy,
                'X-Stations-SourcePath'  => $stSrcPath,
                'X-Stations-AutoScaleK'  => is_null($stAutoScaleK)?'na':sprintf('%.3g',$stAutoScaleK),
                // Meteo debug
                'X-Meteo-Applied'    => $useMeteo ? ($meteoInfo['applied'] ? '1' : '0') : 'na',
                'X-Meteo-Why'        => $useMeteo ? $meteoInfo['why'] : 'na',
                'X-Meteo-Run'        => $useMeteo ? $meteoInfo['run'] : 'na',
                'X-Meteo-Fields'     => $useMeteo ? $meteoInfo['fields'] : 'na',
                'X-Meteo-FactorMin'  => $useMeteo ? $meteoInfo['factor_min'] : 'na',
                'X-Meteo-FactorMax'  => $useMeteo ? $meteoInfo['factor_max'] : 'na',
                'X-Meteo-FactorMean' => $useMeteo ? $meteoInfo['factor_mean'] : 'na',
                'X-Meteo-BetaW'      => $useMeteo ? sprintf('%.3f', $betaW) : 'na',
                'X-Meteo-WS0'        => $useMeteo ? sprintf('%.3f', $WS0) : 'na',
                'X-Meteo-BetaBLH'    => $useMeteo ? sprintf('%.3f', $betaBLH) : 'na',
                'X-Meteo-BLH0'       => $useMeteo ? sprintf('%.3f', $BLH0) : 'na',
                'X-Meteo-FactorBLH-Min'  => $useMeteo ? ($meteoInfo['factor_blh_min'] ?? 'na') : 'na',
                'X-Meteo-FactorBLH-Max'  => $useMeteo ? ($meteoInfo['factor_blh_max'] ?? 'na') : 'na',
                'X-Meteo-FactorBLH-Mean' => $useMeteo ? ($meteoInfo['factor_blh_mean'] ?? 'na') : 'na',
                'X-Meteo-Fmin'       => $useMeteo ? sprintf('%.2f',$fmin) : 'na',
                'X-Meteo-Fmax'       => $useMeteo ? sprintf('%.2f',$fmax) : 'na',
            ];

            /* ---------- 10.1) JSON output branch ---------- */
            if ($format === 'json') {
                // Sanitize the matrix for JSON (NaN/Inf -> null, clamp to [0, cap])
                $Fjson = $this->matrixToJsonSafe($F, $cap); // NEW

                $out = [
                    'succeed' => true,
                    'status'  => 200,
                    'product' => $product,
                    'units'   => $unit,
                    'z'       => $z,
                    't'       => sprintf('+%dh', $t),
                    'bbox'    => $bbox,
                    'grid_deg'=> $grid,
                    'shape'   => [$H, $W],
                    'domain'  => [$vmin, $vmax],
                    'valid_ratio' => ($totCnt>0 ? (100.0*$validCnt/$totCnt) : 0.0),
                    'stats'   => $st,
                    'forecast'=> [
                        'mode'   => $useStations && $product==='no2' ? 'fusion-stations' : 'tempo-only',
                        'source' => $useStations && $product==='no2' ? 'tempo+stations' : 'tempo',
                        'proxy'  => $useStations && $product==='no2' ? 'stations-idw' : 'none',
                    ],
                    'stations'=> [
                        'used'       => ($useStations && $product==='no2') ? ($stationsUsed ? 1 : 0) : 0,
                        'count'      => $stationsCnt,
                        'mean_age_h' => $stationsMeanAge,
                        'grid_cover' => $gridCoverPct,
                        'unit'       => $stUnitHdr,
                        'unit_mismatch'=> $stUnitMismatch,
                        'source_ts'  => $stSourceTs,
                        'why'        => $stWhy,
                        'source_path'=> $stSrcPath,
                        'autoscale_k'=> $stAutoScaleK,
                    ],
                    'meteo'   => [
                        'applied' => $useMeteo ? (bool)$meteoInfo['applied'] : null,
                        'why'     => $useMeteo ? $meteoInfo['why'] : null,
                        'run'     => $useMeteo ? $meteoInfo['run'] : null,
                        'fields'  => $useMeteo ? $meteoInfo['fields'] : null,
                        'factor'  => $useMeteo ? [
                            'min'  => $meteoInfo['factor_min'],
                            'max'  => $meteoInfo['factor_max'],
                            'mean' => $meteoInfo['factor_mean'],
                        ] : null,
                        'factor_blh' => $useMeteo ? [
                            'min'  => $meteoInfo['factor_blh_min'],
                            'max'  => $meteoInfo['factor_blh_max'],
                            'mean' => $meteoInfo['factor_blh_mean'],
                        ] : null,
                        'params' => $useMeteo ? [
                            'beta_w'=>$betaW,'ws0'=>$WS0,
                            'beta_blh'=>$betaBLH,'blh0'=>$BLH0,
                            'fmin'=>$fmin,'fmax'=>$fmax,
                        ] : null,
                    ],
                    //'data'    => $Fjson, // NEW: include if you want full matrix in JSON
                ];

                $jsonHeaders = array_merge($headers, [
                    'Content-Type' => 'application/json',
                    'Cache-Control'=> 'public, max-age=300',
                ]);
                return response()->json($out, 200, $jsonHeaders);
            }

            /* ---------- 11) Render PNG branch (default) ---------- */
            if (!function_exists('imagecreatetruecolor')) {
                return response()->json(['succeed'=>false,'status'=>500,'message'=>"GD not enabled (php-gd)."], 500);
            }
            [$OUT_W, $OUT_H] = $this->sizeForZoom($z);

            // Create transparent canvas
            $im = imagecreatetruecolor($OUT_W, $OUT_H);
            imagealphablending($im, false);
            imagesavealpha($im, true);
            $transparent = imagecolorallocatealpha($im, 0, 0, 0, 127);
            imagefilledrectangle($im, 0, 0, $OUT_W-1, $OUT_H-1, $transparent);

            // Build palette and allocate GD colors (with alpha for low bins)
            $palette = $this->buildPalette($paletteName ?: ($spec['palette'] ?? 'viridis'));
            $nBins   = count($palette);
            $alphaBins = $this->lowBinAlphaProfile($nBins);

            $binColors = [];
            foreach ($palette as $i => $hex) {
                [$r,$g2,$b] = $this->hexToRgb($hex);
                $a = $alphaBins[$i] ?? 0;
                $binColors[$i] = imagecolorallocatealpha($im, $r, $g2, $b, $a);
            }

            // Nearest-neighbor expansion from HxW to OUT_WxOUT_H
            $sx = $OUT_W / max(1,$W);
            $sy = $OUT_H / max(1,$H);

            for ($y=0; $y<$H; $y++) {
                $row = $F[$y] ?? null;
                if (!is_array($row)) continue;
                $y0 = (int)floor($y * $sy);
                $y1 = (int)floor(($y+1) * $sy) - 1;
                if ($y1 < $y0) $y1 = $y0;

                for ($x=0; $x<$W; $x++) {
                    $v = $row[$x] ?? null;
                    if (!is_finite($v)) continue;
                    if (!$allowZero && $v <= 0.0) continue;

                    $tN = ($v - $vmin) / max(self::EPS, ($vmax - $vmin));
                    if ($tN < 0) $tN = 0; if ($tN > 1) $tN = 1;
                    $bin = (int)floor($tN * (max(1,$nBins)-1));
                    if ($bin < 0) $bin = 0; if ($bin >= $nBins) $bin = $nBins-1;
                    $col = $binColors[$bin];

                    $x0 = (int)floor($x * $sx);
                    $x1 = (int)floor(($x+1) * $sx) - 1;
                    if ($x1 < $x0) $x1 = $x0;

                    imagefilledrectangle($im, $x0, $y0, $x1, $y1, $col);
                }
            }

            // Optional debug: draw white dots at station positions used/loaded
            if ($stationsDebug) {
                $stDbg = $this->lastLoadedStationsForDebug ?? null;
                if (!$stDbg) $stDbg = $this->loadStationsForProduct($product, ($product==='o3tot'?'o3':$product), $stMaxAgeH, $stForce);
                if (is_array($stDbg) && !empty($stDbg['points'])) {
                    $white = imagecolorallocatealpha($im, 255,255,255, 0);
                    foreach ($stDbg['points'] as $p) {
                        if (!isset($p['lat'],$p['lon'])) continue;
                        $lat = (float)$p['lat']; $lon=(float)$p['lon'];
                        $px = $this->lonToX($lon, $bbox, $OUT_W);
                        $py = $this->latToY($lat, $bbox, $OUT_H);
                        if ($px<0||$px>=$OUT_W||$py<0||$py>=$OUT_H) continue;
                        imagefilledellipse($im, $px, $py, 4, 4, $white);
                    }
                }
            }

            // Save PNG to cache and clean up GD handle
            imagealphablending($im, true);
            imagepng($im, $pngPath);
            imagedestroy($im);

            /* ---------- 12) Serve PNG ---------- */
            $bin = @file_get_contents($pngPath);
            if ($bin === false) return response()->json(['succeed'=>false,'status'=>500,'message'=>'png io failed'], 500);

            $etag = '"' . md5_file($pngPath) . '"';
            $srcMTime = (int)@filemtime($pngPath);
            $headers = array_merge($headers, [
                'Content-Type'  => 'image/png',
                'ETag'          => $etag,
                'Last-Modified' => gmdate('D, d M Y H:i:s \G\M\T', $srcMTime),
            ]);

            // Conditional GET (If-None-Match)
            $reqEtags = (string)($_SERVER['HTTP_IF_NONE_MATCH'] ?? '');
            if ($reqEtags !== '' && strpos($reqEtags, $etag) !== false) {
                return response('', 304, $headers);
            }
            return response($bin, 200, $headers);

        } catch (\Throwable $e) {
            // Robust error envelope (no stack traces)
            return response()->json([
                'succeed'=>false,'status'=>500,
                'message'=>'internal error','error'=>$e->getMessage()
            ], 500);
        }
    }

    /* ======================== Meteo (Wind & BLH) ======================== */

    /**
     * Load weather index and the +t hour payload from:
     *   storage/app/weather/meteo/json/index.json
     *   storage/app/weather/meteo/json/<latest_run>/+{t}h.json
     * Returns associative array with keys: run, bbox, shape, and optional u10/v10/blh 2D arrays.
     */
    private function loadMeteoForHour(int $t)
    {
        $base = storage_path('app/weather/meteo/json');
        $indexPath = "{$base}/index.json";
        $idx = $this->readJsonSimple($indexPath);
        if (!is_array($idx)) return null;

        $run = $idx['latest_run'] ?? ($idx['cycle'] ?? null);
        if (!is_string($run) || $run==='') return null;

        // Prefer exact +t; otherwise try descending from t..1
        $cand = [];
        for ($dt = $t; $dt>=1; $dt--) $cand[] = sprintf("%s/+%dh.json", "{$base}/{$run}", $dt);

        $payload = null; $pathUsed = null;
        foreach ($cand as $p) {
            $payload = $this->readJsonSimple($p);
            if (is_array($payload)) { $pathUsed = $p; break; }
        }
        if (!is_array($payload)) return ['why'=>'no_hour', 'run'=>$run];

        $out = [
            'run'   => $run,
            'bbox'  => $payload['bbox']  ?? ($idx['bbox'] ?? null),
            'shape' => $payload['shape'] ?? ($idx['shape'] ?? null),
        ];
        if (isset($payload['u10'])) $out['u10'] = $payload['u10'];
        if (isset($payload['v10'])) $out['v10'] = $payload['v10'];
        if (isset($payload['blh'])) $out['blh'] = $payload['blh'];
        $out['__path'] = $pathUsed;
        return $out;
    }

    /**
     * Strict checker for meteo-vs-product shape and bbox compatibility.
     */
    private function shapeAndBoxMatch(array $M, array $shape, array $bbox): bool {
        $okShape = (isset($M['shape'][0],$M['shape'][1]) &&
                    (int)$M['shape'][0]===(int)$shape[0] &&
                    (int)$M['shape'][1]===(int)$shape[1]);
        $okBox = (isset($M['bbox'][0],$M['bbox'][1],$M['bbox'][2],$M['bbox'][3]) &&
                  abs((float)$M['bbox'][0]-(float)$bbox[0])<1e-6 &&
                  abs((float)$M['bbox'][1]-(float)$bbox[1])<1e-6 &&
                  abs((float)$M['bbox'][2]-(float)$bbox[2])<1e-6 &&
                  abs((float)$M['bbox'][3]-(float)$bbox[3])<1e-6);
        return $okShape && $okBox;
    }

    /**
     * Apply multiplicative factor from 10m wind (u10, v10).
     *   ws = sqrt(u10^2 + v10^2)
     *   factor_wind = clamp( exp( beta_w * ln( (ws+eps) / (WS0+eps) ) ), fmin, fmax )
     *   F(y,x) <- clamp( F(y,x) * factor_wind(y,x), 0, cap )
     * Returns stats about applied factors or ['applied'=>false] if not applied.
     */
    private function applyMeteoWindFactor(array &$F, array $U, array $V, int $H, int $W,
                                          float $betaW, float $WS0,
                                          float $fmin, float $fmax,
                                          float $cap, bool $allowZero): array
    {
        $eps = 1e-6; $sum=0.0; $cnt=0; $fminObs=INF; $fmaxObs=-INF;
        for ($y=0; $y<$H; $y++) {
            $rowF = &$F[$y];
            $rowU = $U[$y] ?? null;
            $rowV = $V[$y] ?? null;
            if (!is_array($rowU) || !is_array($rowV)) continue;

            for ($x=0; $x<$W; $x++) {
                $fval = $rowF[$x];
                if (!is_finite($fval)) continue;

                $u = $this->toFloat($rowU[$x] ?? null);
                $v = $this->toFloat($rowV[$x] ?? null);
                if (!is_finite($u) || !is_finite($v)) continue;

                $ws = sqrt($u*$u + $v*$v);
                $ratio = log( max($eps, $ws + $eps) / max($eps, $WS0 + $eps) );
                $factor = exp($betaW * $ratio);
                if ($factor < $fmin) $factor = $fmin;
                if ($factor > $fmax) $factor = $fmax;

                $fminObs = min($fminObs, $factor);
                $fmaxObs = max($fmaxObs, $factor);
                $sum += $factor; $cnt++;

                $nv = $fval * $factor;
                if (!$allowZero && $nv <= 0.0) { $rowF[$x] = NAN; continue; }
                $rowF[$x] = max(0.0, min($cap, $nv));
            }
            unset($rowF);
        }
        if ($cnt === 0) return ['applied'=>false];
        return ['applied'=>true, 'fmean'=>$sum/$cnt, 'fmin'=>$fminObs, 'fmax'=>$fmaxObs];
    }

    /**
     * Apply multiplicative factor from Boundary Layer Height (BLH).
     *   factor_blh = clamp( exp( beta_blh * ln( (blh+eps) / (BLH0+eps) ) ), fmin, fmax )
     * Returns stats about applied factors or ['applied'=>false] if not applied.
     */
    private function applyMeteoBLHFactor(array &$F, array $BLH, int $H, int $W,
                                         float $betaBLH, float $BLH0,
                                         float $fmin, float $fmax,
                                         float $cap, bool $allowZero): array
    {
        $eps = 1e-6; $sum=0.0; $cnt=0; $fminObs=INF; $fmaxObs=-INF;

        for ($y=0; $y<$H; $y++) {
            $rowF = &$F[$y];
            $rowB = $BLH[$y] ?? null;
            if (!is_array($rowB)) continue;

            for ($x=0; $x<$W; $x++) {
                $fval = $rowF[$x];
                if (!is_finite($fval)) continue;

                $blh = $this->toFloat($rowB[$x] ?? null);
                if (!is_finite($blh)) continue;

                $ratio = log( max($eps, $blh + $eps) / max($eps, $BLH0 + $eps) );
                $factor = exp($betaBLH * $ratio);
                if ($factor < $fmin) $factor = $fmin;
                if ($factor > $fmax) $factor = $fmax;

                $fminObs = min($fminObs, $factor);
                $fmaxObs = max($fmaxObs, $factor);
                $sum += $factor; $cnt++;

                $nv = $fval * $factor;
                if (!$allowZero && $nv <= 0.0) { $rowF[$x] = NAN; continue; }
                $rowF[$x] = max(0.0, min($cap, $nv));
            }
            unset($rowF);
        }
        if ($cnt === 0) return ['applied'=>false];
        return ['applied'=>true, 'fmean'=>$sum/$cnt, 'fmin'=>$fminObs, 'fmax'=>$fmaxObs];
    }

    /* ======================== Helpers ======================== */

    /**
     * Per-product units, cap, palette, and quantile domain hints.
     */
    private function productSpec(string $product): array {
        switch ($product) {
            case 'no2':
                return ['units'=>'molec/cm²','cap'=>1.2e16,'qLow'=>0.10,'qHigh'=>0.98,'palette'=>'viridis','allowZero'=>false];
            case 'hcho':
                return ['units'=>'molec/cm²','cap'=>1.0e16,'qLow'=>0.10,'qHigh'=>0.98,'palette'=>'viridis','allowZero'=>false];
            case 'o3tot':
                return ['units'=>'DU','cap'=>700.0,'qLow'=>0.05,'qHigh'=>0.98,'palette'=>'viridis','allowZero'=>false];
            case 'cldo4':
                return ['units'=>'fraction (0..1)','cap'=>1.0,'qLow'=>0.00,'qHigh'=>0.98,'palette'=>'gray','allowZero'=>true];
        }
        // Fallback defaults
        return ['units'=>'','cap'=>1.0,'qLow'=>0.10,'qHigh'=>0.98,'palette'=>'viridis','allowZero'=>false];
    }

    /**
     * Estimate [vmin, vmax] by quantiles with a minimum span safeguard.
     */
    private function estimateDomainAuto($data, float $cap, float $qLow, float $qHigh, bool $allowZero): array
    {
        $qLow  = max(0.0, min(0.49, $qLow));
        $qHigh = max($qLow + 0.01, min(0.999, $qHigh));

        $vals = [];
        if (is_array($data)) {
            if (is_array(reset($data))) {
                foreach ($data as $row) {
                    if (!is_array($row)) continue;
                    foreach ($row as $v) {
                        if (!is_numeric($v)) continue;
                        $v = (float)$v;
                        if (!$allowZero && $v <= 0.0) continue;
                        $v = max(0.0, min($cap, $v));
                        $vals[] = $v;
                    }
                }
            } else {
                foreach ($data as $v) {
                    if (!is_numeric($v)) continue;
                    $v = (float)$v;
                    if (!$allowZero && $v <= 0.0) continue;
                    $v = max(0.0, min($cap, $v));
                    $vals[] = $v;
                }
            }
        }

        if (empty($vals)) return [0.0, $cap];
        sort($vals);
        $n = count($vals);
        $pL = max(0, min($n-1, (int)floor($n*$qLow)));
        $pU = max(0, min($n-1, (int)ceil($n*$qHigh)));
        $L = max(0.0, min($cap, $vals[$pL]));
        $U = max($L + self::EPS, min($cap, $vals[$pU]));

        // Safety: enforce a reasonable minimum display span
        $overallSpan = max(self::EPS, $vals[$n-1] - $vals[0]);
        $minSpan = max(0.01 * $cap, 0.05 * $overallSpan);
        if (($U - $L) < $minSpan) {
            $mid = 0.5 * ($L + $U);
            $L = max(0.0, $mid - 0.5*$minSpan);
            $U = min($cap, $mid + 0.5*$minSpan);
            if ($U <= $L) $U = $L + self::EPS;
        }
        return [$L, $U];
    }

    /**
     * Build named palettes. `gray` is used for cloud fraction; `viridis` for scalar fields.
     */
    private function buildPalette(string $name): array
    {
        $name = strtolower($name);
        if ($name === 'gray' || $name === 'greys' || $name === 'cldo4gray') {
            return [
                '#0a0a0a','#1a1a1a','#2a2a2a','#3a3a3a',
                '#4a4a4a','#5a5a5a','#6a6a6a','#7a7a7a',
                '#8a8a8a','#9a9a9a','#aaaaaa','#bababa',
                '#cacaca','#dadada','#eaeaea','#f5f5f5',
            ];
        }
        // Viridis 16-bin approximation (dark purple -> yellow-green)
        return [
            '#440154','#481467','#482878','#3e4a89',
            '#31688e','#26828e','#1f9e89','#22a884',
            '#44bf70','#73d055','#95d840','#b8de29',
            '#dfe318','#f4e61e','#f9e721','#fde725',
        ];
    }

    /**
     * Alpha profile: make the lowest color bins more transparent to hint low signal over basemap.
     */
    private function lowBinAlphaProfile(int $n): array
    {
        $a = array_fill(0, $n, 0);
        if ($n>0) $a[0]=112; if ($n>1) $a[1]=96; if ($n>2) $a[2]=64;
        return $a;
    }

    /** Hex -> [r,g,b] */
    private function hexToRgb(string $hex): array
    {
        $hex = ltrim($hex, '#');
        return [hexdec(substr($hex,0,2)), hexdec(substr($hex,2,2)), hexdec(substr($hex,4,2))];
    }

    /**
     * Output size per zoom. These are not web-merc tiles, just convenient PNG sizes for UI.
     */
    private function sizeForZoom(int $z): array
    {
        switch ($z) {
            case 3:  return [384, 192];
            case 4:  return [512, 256];
            case 5:  return [768, 384];
            case 6:  return [1024, 512];
            case 7:  return [1280, 640];
            case 8:  return [1536, 768];
            default: return [384, 192];
        }
    }

    /** Count finite values vs total cells */
    private function countFinite(array $F): array {
        $cnt=0; $tot=0;
        foreach ($F as $row) foreach ($row as $v) { $tot++; if (is_finite($v)) $cnt++; }
        return [$cnt,$tot];
    }

    /**
     * Stats summary (min/p10/p50/p90/max + count + unique count) excluding invalid/<=0 if allowZero=false.
     */
    private function statsSummary(array $M, float $cap, bool $allowZero): array {
        $vals = [];
        foreach ($M as $row) {
            foreach ($row as $v) {
                if (!is_finite($v)) continue;
                if (!$allowZero && $v <= 0.0) continue;
                $v = max(0.0, min($cap, (float)$v));
                $vals[] = $v;
            }
        }
        if (empty($vals)) {
            return ['count'=>0,'min'=>null,'p10'=>null,'p50'=>null,'p90'=>null,'max'=>null,'uniq'=>0];
        }
        sort($vals);
        $n = count($vals);
        $q = function($p) use ($vals,$n){ $i = max(0,min($n-1,(int)floor($p*($n-1)))); return $vals[$i]; };
        $uniq = count(array_unique($vals, SORT_REGULAR));
        return [
            'count'=>$n,
            'min'=>$vals[0],
            'p10'=>$q(0.10),
            'p50'=>$q(0.50),
            'p90'=>$q(0.90),
            'max'=>$vals[$n-1],
            'uniq'=>$uniq
        ];
    }

    /**
     * Serve PNG from cache with ETag/Last-Modified support. Returns null if not found or unreadable.
     */
    private function serveCachedPng(Request $req, string $path) {
        if (!is_file($path)) return null;
        $etag = '"' . md5_file($path) . '"';
        $srcMTime = (int)@filemtime($path);
        $headers = [
            'Content-Type'  => 'image/png',
            'Cache-Control' => 'public, max-age=600',
            'ETag'          => $etag,
            'Last-Modified' => gmdate('D, d M Y H:i:s \G\M\T', $srcMTime),
        ];
        $reqEtags = (string)($_SERVER['HTTP_IF_NONE_MATCH'] ?? '');
        if ($reqEtags !== '' && strpos($reqEtags, $etag) !== false) {
            return response('', 304, $headers);
        }
        $bin = @file_get_contents($path);
        if ($bin === false) return null;
        return response($bin, 200, $headers);
    }

    /** Safe float cast: numeric -> float, else NaN */
    private function toFloat($v): float { if ($v === null) return NAN; if (is_numeric($v)) return (float)$v; return NAN; }

    /** HOD accessor with bounds checks */
    private function hodAt(array $HOD, int $hour, int $y, int $x): float {
        $slice = $HOD[$hour] ?? null;
        $row = (is_array($slice)?($slice[$y] ?? null):null);
        if (!is_array($row)) return NAN;
        return $this->toFloat($row[$x] ?? null);
    }

    /** Allocate HxW float matrix filled with NaN */
    private function allocFloat2D(int $H, int $W): array {
        $row = array_fill(0, $W, NAN);
        $M = [];
        for ($i=0; $i<$H; $i++) $M[$i] = $row;
        return $M;
    }

    /* ======================== Stations IO & math ======================== */

    /** Map product to station folder name (o3tot -> o3) */
    private function stationDirFor(string $product): string {
        return $product === 'o3tot' ? 'o3' : $product; // no2->no2 , o3tot->o3
    }

    /**
     * Load latest station dataset for product (or descend by time) and normalize to:
     *   ['points'=>[{lat,lon,val,age_h,provider?},...], 'unit'=>..., 'ts'=>..., 'src'=>..., 'why'=>...]
     * Supports JSON, .gz JSON, NDJSON, and simple CSV headers if needed.
     */
    private function loadStationsForProduct(string $product, ?string $paramHint, float $stMaxAgeH, bool $stForce): array
    {
        $dir  = $this->stationDirFor($product);
        $base = storage_path("app/stations/{$dir}/json");

        $indexPath = "{$base}/index.json";
        $idx = $this->readJsonSimple($indexPath);

        // Gather candidate timestamps from index or from hours/ listing
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

        // Deduplicate and sort descending by normalized Z time
        $seen=[]; $cand2=[];
        foreach ($candTimes as $c) { if (isset($seen[$c['norm']])) continue; $seen[$c['norm']]=1; $cand2[]=$c; }
        usort($cand2, fn($a,$b)=>strcmp($b['norm'],$a['norm']));

        // Try each candidate, parse and normalize
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

                $norm = $this->normalizeStationsPayload($payload, $c['z'], $paramHint);
                $points = $norm['points'] ?? [];
                if (!empty($points)) {
                    // Age filter (unless force=1)
                    if (!$stForce && isset($norm['ts']) && is_string($norm['ts'])) {
                        $ts = strtotime(rtrim($norm['ts'],'Z').'Z');
                        if ($ts !== false) {
                            $ageH = max(0.0, (time() - $ts)/3600.0);
                            if ($ageH > $stMaxAgeH) {
                                continue;
                            }
                        }
                    }
                    $norm['src'] = $p;
                    $this->lastLoadedStationsForDebug = ['points'=>$norm['points'] ?? []];
                    return $norm;
                }
            }
        }

        return ['points'=>[], 'unit'=>null, 'ts'=>null, 'why'=>'empty_data', 'src'=>"{$base}/hours/*"];
    }

    /**
     * Normalize heterogeneous station payloads (arrays, dicts, FeatureCollection, NDJSON, CSV-as-dicts)
     * into a uniform structure. Filters by paramHint if provided.
     */
    private function normalizeStationsPayload($payload, ?string $fileTs, ?string $paramHint=null): array
    {
        $out = ['points'=>[], 'unit'=>null, 'ts'=>$fileTs, 'why'=>'ok'];
        $unit = null;
        $paramHint = $paramHint ? strtolower($paramHint) : null;

        if (is_array($payload) && empty($payload)) {
            return ['points'=>[], 'unit'=>null, 'ts'=>$fileTs, 'why'=>'empty_data'];
        }

        // Case 1: array of rows (list)
        if (is_array($payload) && isset($payload[0]) && is_array($payload[0])) {
            foreach ($payload as $p) {
                $param = strtolower((string)($p['parameter'] ?? $p['pollutant'] ?? $p['param'] ?? ''));
                if ($paramHint && $param && $param !== $paramHint) continue;

                $lat = $p['lat'] ?? ($p['latitude'] ?? null);
                $lon = $p['lon'] ?? ($p['longitude'] ?? null);
                $val = $p['val'] ?? ($p['value'] ?? ($p['concentration'] ?? null));
                $ts  = $p['ts'] ?? ($p['time'] ?? ($p['timestamp'] ?? null));
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

        // Case 2: dict-of-rows (non-numeric keys)
        if (is_array($payload) && empty($payload[0]) && count($payload) > 0) {
            foreach (array_values($payload) as $p) {
                if (!is_array($p)) continue;
                $param = strtolower((string)($p['parameter'] ?? $p['pollutant'] ?? $p['param'] ?? ''));
                if ($paramHint && $param && $param !== $paramHint) continue;

                $lat = $p['lat'] ?? ($p['latitude'] ?? ($p['Latitude'] ?? null));
                $lon = $p['lon'] ?? ($p['longitude']?? ($p['Longitude']?? null));

                // Try nested coords if not present
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

        // Case 3: GeoJSON FeatureCollection of Points
        if (is_array($payload) && ($payload['type'] ?? null) === 'FeatureCollection' && isset($payload['features'])) {
            foreach ($payload['features'] as $f) {
                $geom = $f['geometry'] ?? null;
                $prop = $f['properties'] ?? [];
                if (!is_array($geom) || ($geom['type'] ?? null) !== 'Point') continue;
                $coords = $geom['coordinates'] ?? null;
                if (!is_array($coords) || count($coords) < 2) continue;

                $param = strtolower((string)($prop['parameter'] ?? $prop['pollutant'] ?? $prop['param'] ?? ''));
                if ($paramHint && $param && $param !== $paramHint) continue;

                $lon = $coords[0]; $lat = $coords[1];
                $val = $prop['val'] ?? ($prop['value'] ?? ($prop['concentration'] ?? null));
                $age = $prop['age_h'] ?? null;
                if (!$unit) $unit = $prop['unit'] ?? ($prop['units'] ?? null);

                if (is_numeric($lat) && is_numeric($lon) && is_numeric($val)) {
                    $out['points'][] = ['lat'=>(float)$lat,'lon'=>(float)$lon,'val'=>(float)$val,'age_h'=>$age];
                }
            }
            $out['unit'] = $unit ?? null;
            if (empty($out['points'])) $out['why'] = 'empty_data';
            return $out;
        }

        // Case 4: NDJSON or CSV parsed into array of dicts
        if (is_array($payload) && isset($payload['_ndjson']) && is_array($payload['_ndjson'])) {
            foreach ($payload['_ndjson'] as $p) {
                $param = strtolower((string)($p['parameter'] ?? $p['pollutant'] ?? $p['param'] ?? ''));
                if ($paramHint && $param && $param !== $paramHint) continue;

                $lat = $p['lat'] ?? ($p['latitude'] ?? null);
                $lon = $p['lon'] ?? ($p['longitude'] ?? null);
                $val = $p['val'] ?? ($p['value'] ?? ($p['concentration'] ?? null));
                $ts  = $p['ts'] ?? ($p['time'] ?? ($p['timestamp'] ?? null));
                $age = null;
                if (is_string($ts)) { $tsp = strtotime($ts); if ($tsp !== false) $age = max(0.0,(time()-$tsp)/3600.0); }
                if (!$unit) $unit = $p['units'] ?? ($p['unit'] ?? null);
                if (is_numeric($lat) && is_numeric($lon) && is_numeric($val)) {
                    $out['points'][] = ['lat'=>(float)$lat,'lon'=>(float)$lon,'val'=>(float)$val,'age_h'=>$age];
                }
            }
            if (empty($out['points'])) $out['why'] = 'empty_data';
            $out['unit'] = $unit ?? null;
            return $out;
        }

        // Case 5: Single row object with lat/lon/value
        if (is_array($payload) && (isset($payload['lat']) || isset($payload['latitude']))) {
            $param = strtolower((string)($payload['parameter'] ?? $payload['pollutant'] ?? $payload['param'] ?? ''));
            if (!$paramHint || ($param && $param === $paramHint)) {
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
                    if (empty($out['points'])) $out['why'] = 'empty_data';
                    return $out;
                }
            }
        }

        return ['points'=>[], 'unit'=>null, 'ts'=>$fileTs, 'why'=>'format_unknown'];
    }

    /**
     * Inverse Distance Weighting (IDW) interpolation onto the product grid.
     * Returns [G, C] where G is interpolated grid and C is coverage count per cell.
     */
    private function idwGrid(array $pts, array $bbox, array $shape, float $radiusKm, float $pow, bool $allowZero, float $cap): array
    {
        $H = (int)$shape[0]; $W = (int)$shape[1];
        $S = (float)$bbox[0]; $N = (float)$bbox[1];
        $Wdeg = (float)$bbox[2]; $Edeg = (float)$bbox[3];

        $G = $this->allocFloat2D($H,$W);
        $C = [];
        for ($i=0; $i<$H; $i++) $C[$i] = array_fill(0,$W,0);

        $dLat = ($H===1)?0.0:(($N - $S)/max(1,($H - 1)));
        $dLon = ($W===1)?0.0:(($Edeg - $Wdeg)/max(1,($W - 1)));

        for ($y=0; $y<$H; $y++) {
            $latg = $S + $dLat*$y;
            $cosLat = cos(deg2rad($latg));
            for ($x=0; $x<$W; $x++) {
                $long = $Wdeg + $dLon*$x;
                $wsum = 0.0; $vsum = 0.0; $cnt=0;

                foreach ($pts as $p) {
                    $plat = isset($p['lat']) ? (float)$p['lat'] : NAN;
                    $plon = isset($p['lon']) ? (float)$p['lon'] : NAN;
                    $pval = isset($p['val']) ? (float)$p['val'] : (isset($p['value']) ? (float)$p['value'] : NAN);
                    if (!is_finite($plat) || !is_finite($plon) || !is_finite($pval)) continue;
                    if (!$allowZero && $pval <= 0.0) continue;
                    $pval = max(0.0, min($cap, $pval));

                    $dKm = $this->fastDistanceKm($latg, $long, $plat, $plon, $cosLat);
                    if ($dKm > $radiusKm) continue;

                    $w = ($dKm <= 1e-6) ? 1e6 : (1.0 / pow($dKm, max(0.1,$pow)));
                    $wsum += $w;
                    $vsum += $w * $pval;
                    $cnt++;
                }

                if ($cnt>0 && $wsum>0) {
                    $G[$y][$x] = $vsum / $wsum;
                    $C[$y][$x] = $cnt;
                } else {
                    $G[$y][$x] = NAN;
                    $C[$y][$x] = 0;
                }
            }
        }
        return [$G,$C];
    }

    /**
     * Fast approximate km distance using lat/long deltas and cos(lat) scaling. Good for small radii.
     */
    private function fastDistanceKm(float $lat1, float $lon1, float $lat2, float $lon2, float $cosLat1): float
    {
        $dlat = ($lat2 - $lat1);
        $dlon = ($lon2 - $lon1);
        $dx = 111.32 * $dlon * $cosLat1;
        $dy = 111.32 * $dlat;
        return sqrt($dx*$dx + $dy*$dy);
    }

    /* ---------- Grid/pixel helpers (linear mapping within bbox) ---------- */
    private function lonToGridX(float $lon, array $bbox, int $W): int {
        $Wdeg = (float)$bbox[2]; $Edeg=(float)$bbox[3];
        $t = ($lon - $Wdeg) / max(self::EPS, ($Edeg - $Wdeg));
        $t = max(0.0, min(1.0, $t));
        $ix = (int)floor($t * ($W - 1));
        if ($ix < 0) $ix = 0; if ($ix >= $W) $ix = $W - 1;
        return $ix;
    }
    private function latToGridY(float $lat, array $bbox, int $H): int {
        $S=(float)$bbox[0]; $N=(float)$bbox[1];
        $t = ($lat - $S) / max(self::EPS, ($N - $S));
        $t = max(0.0, min(1.0, $t));
        $iy = (int)floor($t * ($H - 1));
        if ($iy < 0) $iy = 0; if ($iy >= $H) $iy = $H - 1;
        return $iy;
    }
    private function lonToX(float $lon, array $bbox, int $W): int {
        $Wdeg = (float)$bbox[2]; $Edeg=(float)$bbox[3];
        $t = ($lon - $Wdeg) / max(self::EPS, ($Edeg - $Wdeg));
        $t = max(0.0, min(1.0, $t));
        return (int)round($t * ($W-1));
    }
    private function latToY(float $lat, array $bbox, int $H): int {
        $S=(float)$bbox[0]; $N=(float)$bbox[1];
        $t = ($lat - $S) / max(self::EPS, ($N - $S));
        $t = max(0.0, min(1.0, $t));
        return (int)round($t * ($H-1));
    }

    /* ======================== JSON readers ======================== */

    /**
     * Robust JSON reader with:
     *  - .gz fallback
     *  - UTF-8 BOM strip
     *  - NaN/Inf sanitization
     *  - one retry if initial parse fails
     * Returns decoded array or error string.
     */
    private function readJsonRobust(string $path)
    {
        try {
            $raw = $this->readTextPossiblyGz($path);
            if ($raw === null) return "latest.json not found or unreadable";
            if (substr($raw, 0, 3) === "\xEF\xBB\xBF") $raw = substr($raw, 3);
            $raw = $this->jsonSanitize($raw);
            $js = json_decode($raw, true, 1024, JSON_INVALID_UTF8_IGNORE);
            if (json_last_error() === JSON_ERROR_NONE) return $js;

            // small retry window
            for ($i=0; $i<2; $i++) {
                usleep(200 * 1000);
                $raw2 = $this->readTextPossiblyGz($path);
                if ($raw2 === null) break;
                if (substr($raw2, 0, 3) === "\xEF\xBB\xBF") $raw2 = substr($raw2, 3);
                $raw2 = $this->jsonSanitize($raw2);
                $js2  = json_decode($raw2, true, 1024, JSON_INVALID_UTF8_IGNORE);
                if (json_last_error() === JSON_ERROR_NONE) return $js2;
            }
            return "json error: " . json_last_error_msg();
        } catch (\Throwable $e) {
            return "exception: " . $e->getMessage();
        }
    }

    /**
     * Simple JSON reader: .gz fallback, BOM strip, and NaN/Inf sanitization.
     * Returns array|null.
     */
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

    /**
     * Replace NaN/Inf tokens and trailing commas; keeps JSON strict.
     */
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

    /**
     * Read text with optional .gz fallback. Returns null if neither path exists/unreadable.
     */
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
                // guard against very large files
                if (strlen($buf) > 600 * 1024 * 1024) { gzclose($fp); return null; }
            }
            gzclose($fp);
            return $buf;
        }
        return null;
    }

    /**
     * Try to parse NDJSON lines or CSV (first row headers) into array of dicts: ['_ndjson'=>[...]].
     */
    private function tryParseNdjsonOrCsv(string $text) {
        $text = trim($text);
        if ($text==='') return null;
        $lines = preg_split("/\r\n|\n|\r/", $text);
        $items = [];
        $commaHeaders = null;

        foreach ($lines as $i=>$ln) {
            $ln = trim($ln);
            if ($ln==='') continue;

            // NDJSON line (simple heuristic)
            if ($ln[0]==='{' && substr($ln,-1)==='}') {
                $js = json_decode($ln, true);
                if (is_array($js)) { $items[] = $js; continue; }
            }

            // CSV fallback: use the first line as headers
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

    /* ======================== NEW: JSON-safe matrix ======================== */

    /**
     * Convert float matrix to a JSON-safe matrix:
     * - Non-finite values (NaN, ±INF) -> null
     * - Finite values clamped to [0, cap]
     */
    private function matrixToJsonSafe(array $M, float $cap): array
    {
        $H = count($M);
        $out = [];
        for ($y=0; $y<$H; $y++) {
            $row = $M[$y] ?? [];
            $W = is_array($row) ? count($row) : 0;
            $rowOut = [];
            for ($x=0; $x<$W; $x++) {
                $v = $row[$x] ?? null;
                if (!is_finite($v)) { $rowOut[] = null; continue; }
                $vv = max(0.0, min($cap, (float)$v));
                $rowOut[] = $vv;
            }
            $out[] = $rowOut;
        }
        return $out;
    }
}
