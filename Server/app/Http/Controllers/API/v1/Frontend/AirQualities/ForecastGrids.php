<?php

namespace App\Http\Controllers\API\V1\Frontend\AirQualities;

use Illuminate\Http\Request;

/**
 * ForecastGrids
 *
 * JSON grids endpoint (z=9..11) with safe, backward-compatible optimizations:
 *  - Clips loops to the effective bbox to speed up small requests
 *  - Emits debug headers (X-Clip-Ranges, X-Cells-Looped)
 *
 * Output/behavior remains compatible with existing consumers (e.g., PointAssess).
 */
class ForecastGrids
{
    /* ---------- Product / zoom / limits ---------- */
    private const PRODUCTS = ['no2','hcho','o3tot','cldo4'];

    // Grids JSON is only allowed for z=9..11 (PNG remains for lower zooms)
    private const Z_MIN = 9;
    private const Z_MAX = 11;

    // Safety: maximum returned cells per zoom to protect performance
    private const MAX_CELLS_BY_Z = [
        9  => 12000,
        10 => 20000,
        11 => 40000,
    ];

    /** HOD ratio clamps + numerical eps (kept identical to Forecast) */
    private const HOD_RATIO_MIN = 0.33;
    private const HOD_RATIO_MAX = 3.0;
    private const EPS            = 1e-9;

    /** keep last loaded stations for debug dots overlay (parity) */
    private $lastLoadedStationsForDebug = null;

    public function build(Request $request)
    {
        try {
            /* ---------- 1) Params ---------- */
            $product = strtolower((string)$request->query('product', 'no2'));
            if (!in_array($product, self::PRODUCTS, true)) {
                return $this->jerr(422, 'invalid product');
            }

            $z = (int)$request->query('z', 9);
            if ($z < self::Z_MIN || $z > self::Z_MAX) {
                return $this->jerr(422, 'invalid z (9..11)');
            }

            // bbox=W,S,E,N (required)
            $bboxStr = (string)$request->query('bbox', '');
            $bboxReq = $this->parseBbox($bboxStr);
            if (!$bboxReq) {
                return $this->jerr(400, 'invalid bbox (expect "W,S,E,N")');
            }
            [$WdegReq,$SdegReq,$EdegReq,$NdegReq] = $bboxReq;

            // domain = auto | fixed:min,max
            $domainParam  = (string)$request->query('domain', 'auto');

            // palette echo (only for parity with overlay-grids)
            $paletteParam = strtolower((string)$request->query('palette', ''));

            // time horizon: accept "+H" or "H" ; 0..12
            $tStr = (string)$request->query('t', '0');
            $t = ($tStr !== '' && $tStr[0] === '+') ? (int)substr($tStr, 1) : (int)$tStr;
            if ($t < 0 || $t > 12) {
                return $this->jerr(422, 't must be 0..12');
            }

            // stations params (NO2 only)
            $useStations       = (int)$request->query('stations', 0) === 1;
            $stationsDebug     = (int)$request->query('stations_debug', 0) === 1;
            $stMaxAgeH         = (float)$request->query('stations_max_age_h', 3.0);
            $stRadiusKm        = (float)$request->query('stations_radius_km', 75.0);
            $stPow             = (float)$request->query('stations_pow', 2.0);
            $stWMax            = (float)$request->query('stations_w_max', 0.60);
            $stAutoScale       = (int)$request->query('stations_autoscale', 1) === 1;
            $stForce           = (int)$request->query('stations_force', 0) === 1;

            // meteorology params (Stage-3)
            $useMeteo      = (int)$request->query('meteo', 0) === 1;
            $betaW         = (float)$request->query('meteo_beta_w',  -0.08);  // wind
            $WS0           = (float)$request->query('meteo_ws0',      3.0);   // ref wind
            $betaBLH       = (float)$request->query('meteo_beta_blh', -0.25); // BLH sens
            $BLH0          = (float)$request->query('meteo_blh0',     800.0); // ref BLH (m)
            $fmin          = (float)$request->query('meteo_fmin',     0.60);
            $fmax          = (float)$request->query('meteo_fmax',     1.60);

            /* ---------- 2) TEMPO paths ---------- */
            $rootTempo  = storage_path("app/tempo/{$product}");
            $fcDir      = "{$rootTempo}/fc_support";
            $latestPath = "{$fcDir}/latest.json";
            $hodDir     = "{$fcDir}/hod";
            $hodMeta    = "{$hodDir}/meta.json";

            if (!is_file($latestPath) && !is_file($latestPath . '.gz')) {
                return $this->jerr(503, 'missing latest.json (run summaries first)');
            }
            if (!is_dir($hodDir)) {
                return $this->jerr(503, 'missing hod/ (run summaries first)');
            }

            /* ---------- 3) Read latest.json ---------- */
            $latest = $this->readJsonRobust($latestPath);
            if (!is_array($latest)) {
                return $this->jerr(500, 'latest.json invalid', ['detail'=>$latest]);
            }

            $shape = $latest['shape'] ?? null;     // [H,W]
            $bbox  = $latest['bbox']  ?? null;     // [S,N,W,E]
            $grid  = $latest['grid_deg'] ?? 0.1;
            if (!is_array($shape) || count($shape)!==2 || !is_array($bbox) || count($bbox)!==4) {
                return $this->jerr(500, 'latest.json missing shape/bbox');
            }

            $V    = $latest['data']['value'] ?? null;   // HxW
            $AGE  = $latest['data']['age_h'] ?? null;   // HxW
            $CLOUD= $latest['data']['cloud'] ?? null;   // optional HxW (0..1), if available
            if (!is_array($V) || !is_array($AGE)) {
                return $this->jerr(500, 'latest.json missing data.value/age_h');
            }

            $H = (int)$shape[0]; $W = (int)$shape[1];
            if ($H <= 0 || $W <= 0) {
                return $this->jerr(500, 'invalid shape');
            }

            // Precompute lon array for local-hour conversion (same as Forecast)
            $Wdeg = (float)$bbox[2];
            $Edeg = (float)$bbox[3];
            $Sdeg = (float)$bbox[0];
            $Ndeg = (float)$bbox[1];
            $lon1d = [];
            $step  = ($W === 1) ? 0.0 : ($Edeg - $Wdeg) / ($W - 1);
            for ($x=0; $x<$W; $x++) $lon1d[$x] = $Wdeg + $step*$x;

            /* ---------- 4) HOD ---------- */
            $HOD = [];
            for ($h=0; $h<24; $h++) {
                $slice = $this->readJsonSimple(sprintf("%s/hour_%02d.json", $hodDir, $h));
                $HOD[$h] = is_array($slice) ? ($slice['data'] ?? null) : null;
            }
            $hodMetaJs = $this->readJsonSimple($hodMeta);
            $newestGid = is_array($hodMetaJs) ? ($hodMetaJs['newest_gid'] ?? null) : null;

            /* ---------- 5) Product spec ---------- */
            $spec = $this->productSpec($product);
            $cap  = (float)$spec['cap'];
            $allowZero = (bool)$spec['allowZero'];
            $defaultPalette = $spec['palette'] ?? 'viridis';
            $paletteName = $paletteParam !== '' ? $paletteParam : $defaultPalette;
            if ($paletteName !== 'gray' && $paletteName !== 'viridis') $paletteName = $defaultPalette;
            $unit = $latest['unit'] ?? ($spec['units'] ?? '');

            /* ---------- 6) TEMPO-only base grid (same logic as Forecast) ---------- */
            $F = $this->allocFloat2D($H, $W);

            if ($t === 0) {
                for ($y=0; $y<$H; $y++) {
                    for ($x=0; $x<$W; $x++) {
                        $v = $this->toFloat($V[$y][$x]);
                        if (!is_finite($v) || (!$allowZero && $v <= 0.0)) { $F[$y][$x] = NAN; continue; }
                        $F[$y][$x] = max(0.0, min($cap, $v));
                    }
                }
            } else {
                for ($y=0; $y<$H; $y++) {
                    for ($x=0; $x<$W; $x++) {
                        $v = $this->toFloat($V[$y][$x]);
                        $ageH = $this->toFloat($AGE[$y][$x]);
                        if (!is_finite($v) || (!$allowZero && $v <= 0.0)) { $F[$y][$x] = NAN; continue; }

                        // HOD forecast using local hour inferred from longitude
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

            /* ---------- 6.2) Meteorology adjustment (Wind + BLH) ---------- */
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

                        // Wind factor
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

                        // BLH factor
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

            /* ---------- 6.5) Stations fusion (NO2-only) ---------- */
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
                    $rawUnit = $st['unit'] ?? '';
                    $stUnitHdr = $rawUnit ? strtolower($rawUnit) : 'na';

                    $isSameUnit = (strpos(strtolower($unit),'molec') !== false) && (strpos($stUnitHdr,'molec') !== false);
                    $stUnitMismatch = !$isSameUnit;

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
                            foreach ($pts as &$q) { $q['val'] = min($cap, max(0.0, $q['val'])); } unset($q);
                        }
                    }

                    $stationsCnt = count($pts);
                    if ($stationsCnt > 0) $stationsMeanAge = $ageSum / $stationsCnt;

                    if ($stationsCnt > 0 && (!$stUnitMismatch || $stForce)) {
                        [$G, $Cov] = $this->idwGrid($pts, $bbox, $shape, $stRadiusKm, $stPow, $allowZero, $cap);
                        $covCnt=0; $tot=$H*$W; for($y2=0;$y2<$H;$y2++) for($x2=0;$x2<$W;$x2++) if($Cov[$y2][$x2]>0) $covCnt++;
                        $gridCoverPct = ($tot>0)? (100.0*$covCnt/$tot) : 0.0;

                        $freshFactor = ($stMaxAgeH>0 && $stationsMeanAge!==null)
                            ? max(0.0, min(1.0, 1.0 - ($stationsMeanAge/$stMaxAgeH))) : 0.0;
                        $w = $stWMax * $freshFactor;

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

            /* ---------- 7) Domain ---------- */
            if (stripos($domainParam, 'fixed:') === 0) {
                $specDom = substr($domainParam, 6);
                $parts = explode(',', $specDom);
                if (count($parts) !== 2) {
                    return $this->jerr(400, 'invalid domain format');
                }
                $vmin = max(0.0, min($cap, (float)$parts[0]));
                $vmax = max($vmin + self::EPS, min($cap, (float)$parts[1]));
                $dom = ['strategy'=>'fixed','min'=>$vmin,'max'=>$vmax];
            } else {
                [$vmin, $vmax] = $this->estimateDomainAuto($F, (float)$spec['cap'], $spec['qLow'], $spec['qHigh'], (bool)$spec['allowZero']);
                $dom = ['strategy'=>'auto','min'=>$vmin,'max'=>$vmax];
            }

            /* ---------- 8) Build cells within requested bbox ---------- */
            // effective bbox = intersection of requested bbox with dataset bbox
            $WdegEff = max($Wdeg, min($Edeg, $WdegReq));
            $EdegEff = max($Wdeg, min($Edeg, $EdegReq));
            $SdegEff = max($Sdeg, min($Ndeg, $SdegReq));
            $NdegEff = max($Sdeg, min($Ndeg, $NdegReq));

            // Cell spacing
            $dLat = ($H===1)?0.0:(($Ndeg - $Sdeg)/max(1,($H - 1)));
            $dLon = ($W===1)?0.0:(($Edeg - $Wdeg)/max(1,($W - 1)));

            // quick count guard for size (approx upper bound)
            $estNY = ($dLat>0) ? (int)floor(($NdegEff - $SdegEff)/$dLat + 2) : $H;
            $estNX = ($dLon>0) ? (int)floor(($EdegEff - $WdegEff)/$dLon + 2) : $W;
            $estCells = max(0, $estNY) * max(0, $estNX);
            $maxCells = self::MAX_CELLS_BY_Z[$z] ?? 20000;
            if ($estCells > $maxCells) {
                return $this->jerr(400, 'bbox too large for z', [
                    'z'=>$z, 'max_cells'=>$maxCells, 'estimated_cells'=>$estCells
                ]);
            }

            // --- Efficient clipping: loop only over indices intersecting bbox_effective ---
            // Map bbox_effective to index ranges [y0..y1], [x0..x1]
            $y0 = 0; $y1 = $H - 1;
            $x0 = 0; $x1 = $W - 1;
            if ($H > 1 && $dLat > 0) {
                $y0 = max(0, min($H-1, (int)floor(($SdegEff - $Sdeg) / max(self::EPS,$dLat))));
                $y1 = max(0, min($H-1, (int)ceil ( ($NdegEff - $Sdeg) / max(self::EPS,$dLat))));
            }
            if ($W > 1 && $dLon > 0) {
                $x0 = max(0, min($W-1, (int)floor(($WdegEff - $Wdeg) / max(self::EPS,$dLon))));
                $x1 = max(0, min($W-1, (int)ceil ( ($EdegEff - $Wdeg) / max(self::EPS,$dLon))));
            }
            if ($y1 < $y0 || $x1 < $x0) { $y0=0; $y1=-1; $x0=0; $x1=-1; } // empty intersection guard

            // A tighter upper-bound with clipped ranges
            $estCellsClipped = max(0, ($y1 - $y0 + 1)) * max(0, ($x1 - $x0 + 1));
            if ($estCellsClipped > $maxCells) {
                return $this->jerr(400, 'bbox too large for z', [
                    'z'=>$z, 'max_cells'=>$maxCells, 'estimated_cells'=>$estCellsClipped
                ]);
            }

            // gather cells (clipped)
            $cells = [];
            $looped = 0;
            for ($y=$y0; $y<=$y1; $y++) {
                $lat = $Sdeg + $dLat*$y;
                if ($lat < $SdegEff - 1e-12 || $lat > $NdegEff + 1e-12) continue;

                for ($x=$x0; $x<=$x1; $x++) {
                    $lon = $Wdeg + $dLon*$x;
                    if ($lon < $WdegEff - 1e-12 || $lon > $EdegEff + 1e-12) continue;
                    $looped++;

                    $v = $F[$y][$x];
                    if (!is_finite($v)) continue;
                    if (!$allowZero && $v <= 0.0) continue;

                    $val = max(0.0, min($cap, (float)$v));
                    $cell = [
                        'lat'   => $lat,
                        'lon'   => $lon,
                        'value' => $val,
                    ];

                    // Optional cloud (0..1) if present in latest.json; clamp to [0,1]
                    if (is_array($CLOUD)) {
                        $cv = $this->toFloat($CLOUD[$y][$x] ?? null);
                        if (is_finite($cv)) {
                            $cell['cloud'] = max(0.0, min(1.0, (float)$cv));
                        }
                    }
                    $cells[] = $cell;

                    if (count($cells) > $maxCells) { // hard cutoff
                        return $this->jerr(400, 'bbox too large for z', [
                            'z'=>$z, 'max_cells'=>$maxCells, 'estimated_cells'=>$estCellsClipped
                        ]);
                    }
                }
            }

            /* ---------- 9) Stats (post all processing) ---------- */
            [$validCnt,$totCnt] = $this->countFinite($F);
            $st = $this->statsSummary($F, $cap, $allowZero);

            /* ---------- 10) Echo helpers & headers ---------- */
            $paletteEcho = $paletteName ?: ($spec['palette'] ?? 'viridis');
            $bucketDeg = (float)$grid; // same bucketing as dataset grid
            $bboxEffective = [
                'w' => $WdegEff,
                's' => $SdegEff,
                'e' => $EdegEff,
                'n' => $NdegEff,
            ];

            // time echo normalization:
            // - t: "+H"
            // - t_utc: now + H hours (UTC ISO8601 Z)
            $tEcho = sprintf('+%d', $t);
            $tUtc  = gmdate('Y-m-d\TH:i:s\Z', time() + $t*3600);

            $headers = [
                'Cache-Control'                => 'public, max-age=300',
                'Access-Control-Allow-Origin'  => '*',
                'X-Grid-Deg'                   => (string)$grid,
                'X-Units'                      => (string)$unit,
                'X-Valid-Ratio'                => ($totCnt>0 ? sprintf('%.1f%%', 100.0*$validCnt/$totCnt) : '0%'),
                'X-Stats-Count'                => (string)$st['count'],
                'X-Stats-Uniq'                 => (string)$st['uniq'],
                'X-Stats-Min'                  => is_null($st['min']) ? 'na' : sprintf('%.6g',$st['min']),
                'X-Stats-P10'                  => is_null($st['p10']) ? 'na' : sprintf('%.6g',$st['p10']),
                'X-Stats-P50'                  => is_null($st['p50']) ? 'na' : sprintf('%.6g',$st['p50']),
                'X-Stats-P90'                  => is_null($st['p90']) ? 'na' : sprintf('%.6g',$st['p90']),
                'X-Stats-Max'                  => is_null($st['max']) ? 'na' : sprintf('%.6g',$st['max']),
                // New safe debug headers:
                'X-Clip-Ranges'                => ($y1 >= $y0 && $x1 >= $x0) ? sprintf('%d:%d,%d:%d',$y0,$y1,$x0,$x1) : 'empty',
                'X-Cells-Looped'               => (string)$looped,
            ];

            // stations headers
            $headers = array_merge($headers, [
                'X-Forecast-Mode'     => $canUseStations ? 'fusion-stations' : 'tempo-only',
                'X-Forecast-Source'   => $canUseStations ? 'tempo+stations' : 'tempo',
                'X-Forecast-Proxy'    => $canUseStations ? 'stations-idw' : 'none',
                'X-Forecast-T'        => $tEcho . 'h',
                'X-Stations-Used'        => $canUseStations && $stationsUsed ? '1' : '0',
                'X-Stations-Count'       => (string)$stationsCnt,
                'X-Stations-MeanAgeH'    => is_null($stationsMeanAge) ? 'na' : sprintf('%.2f', $stationsMeanAge),
                'X-Stations-GridCover'   => sprintf('%.3f%%', $gridCoverPct),
                'X-Stations-Unit'        => $stUnitHdr,
                'X-Stations-UnitMismatch'=> $stUnitMismatch ? '1' : '0',
                'X-Stations-SourceTs'    => $stSourceTs,
                'X-Stations-Why'         => $stWhy,
                'X-Stations-SourcePath'  => $stSrcPath,
                'X-Stations-AutoScaleK'  => is_null($stAutoScaleK)?'na':sprintf('%.3g',$stAutoScaleK),
            ]);

            // meteo headers
            if ($useMeteo) {
                $headers = array_merge($headers, [
                    'X-Meteo-Applied'    => $meteoInfo['applied'] ? '1' : '0',
                    'X-Meteo-Why'        => $meteoInfo['why'],
                    'X-Meteo-Run'        => $meteoInfo['run'],
                    'X-Meteo-Fields'     => $meteoInfo['fields'],
                    'X-Meteo-FactorMin'  => $meteoInfo['factor_min'],
                    'X-Meteo-FactorMax'  => $meteoInfo['factor_max'],
                    'X-Meteo-FactorMean' => $meteoInfo['factor_mean'],
                    'X-Meteo-BetaW'      => sprintf('%.3f', $betaW),
                    'X-Meteo-WS0'        => sprintf('%.3f', $WS0),
                    'X-Meteo-BetaBLH'    => sprintf('%.3f', $betaBLH),
                    'X-Meteo-BLH0'       => sprintf('%.3f', $BLH0),
                    'X-Meteo-Fmin'       => sprintf('%.2f',$fmin),
                    'X-Meteo-Fmax'       => sprintf('%.2f',$fmax),
                ]);
            }

            /* ---------- 11) JSON response ---------- */
            $out = [
                'succeed' => true,
                'status'  => 200,
                'product' => $product,
                'units'   => $unit,
                'mode'    => 'forecast',
                'z'       => $z,
                't'       => $tEcho,                  // normalized "+H"
                't_utc'   => $tUtc,                   // absolute target UTC (helper for clients)
                'bbox'    => ['w'=>$WdegReq,'s'=>$SdegReq,'e'=>$EdegReq,'n'=>$NdegReq],
                'bbox_effective' => $bboxEffective,   // intersection actually processed
                'grid_deg'=> $grid,
                'bucket_deg'=> $bucketDeg,            // echo bucket size for caching strategies
                'palette' => $paletteEcho,
                'domain'  => $dom,
                'stats'   => $st,                     // stats AFTER all processing (fusion/clamp/meteo)
                'cells'   => $cells,
                'forecast'=> [
                    'mode'   => $canUseStations && $product==='no2' ? 'fusion-stations' : 'tempo-only',
                    'source' => $canUseStations && $product==='no2' ? 'tempo+stations' : 'tempo',
                    'proxy'  => $canUseStations && $product==='no2' ? 'stations-idw' : 'none',
                ],
                'stations'=> [
                    'used'       => ($useStations && $product==='no2') ? ($stationsUsed ? 1 : 0) : 0,
                    'count'      => $stationsCnt,
                    'mean_age_h' => $stationsMeanAge,
                    'grid_cover' => $gridCoverPct,
                    'unit'       => $stUnitHdr,
                    'unit_mismatch'=> $stUnitMismatch,
                    'source_ts'  => $stSourceTs,
                    'why'        => $useStations ? $stWhy : 'off', // explicit echo
                    'source_path'=> $stSrcPath,
                    'autoscale_k'=> $stAutoScaleK,
                ],
                'meteo'   => $useMeteo ? [
                    'applied' => (bool)$meteoInfo['applied'],
                    'why'     => $meteoInfo['why'],
                    'run'     => $meteoInfo['run'],
                    'fields'  => $meteoInfo['fields'],
                    'factor'  => [
                        'min'  => $meteoInfo['factor_min'],
                        'max'  => $meteoInfo['factor_max'],
                        'mean' => $meteoInfo['factor_mean'],
                    ],
                    'factor_blh' => [
                        'min'  => $meteoInfo['factor_blh_min'],
                        'max'  => $meteoInfo['factor_blh_max'],
                        'mean' => $meteoInfo['factor_blh_mean'],
                    ],
                    'params' => [
                        'beta_w'=>$betaW,'ws0'=>$WS0,
                        'beta_blh'=>$betaBLH,'blh0'=>$BLH0,
                        'fmin'=>$fmin,'fmax'=>$fmax,
                    ],
                ] : [
                    'applied'=>null,'why'=>null,'run'=>null,'fields'=>null,'factor'=>null,'factor_blh'=>null,'params'=>null
                ],
            ];

            return response()->json($out, 200, array_merge($headers, [
                'Content-Type' => 'application/json; charset=utf-8'
            ]));

        } catch (\Throwable $e) {
            return $this->jerr(500, 'internal error', ['error'=>$e->getMessage()]);
        }
    }

    /* ======================== Helpers (parity with Forecast) ======================== */

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

    private function productSpec(string $product): array {
        switch ($product) {
            case 'no2':
                return ['units'=>'molecules/cm^2','cap'=>1.2e16,'qLow'=>0.10,'qHigh'=>0.98,'palette'=>'viridis','allowZero'=>false];
            case 'hcho':
                return ['units'=>'molecules/cm^2','cap'=>1.0e16,'qLow'=>0.10,'qHigh'=>0.98,'palette'=>'viridis','allowZero'=>false];
            case 'o3tot':
                return ['units'=>'DU','cap'=>700.0,'qLow'=>0.05,'qHigh'=>0.98,'palette'=>'viridis','allowZero'=>false];
            case 'cldo4':
                return ['units'=>'fraction (0..1)','cap'=>1.0,'qLow'=>0.00,'qHigh'=>0.98,'palette'=>'gray','allowZero'=>true];
        }
        return ['units'=>'','cap'=>1.0,'qLow'=>0.10,'qHigh'=>0.98,'palette'=>'viridis','allowZero'=>false];
    }

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

    private function allocFloat2D(int $H, int $W): array {
        $row = array_fill(0, $W, NAN);
        $M = [];
        for ($i=0; $i<$H; $i++) $M[$i] = $row;
        return $M;
    }

    private function countFinite(array $F): array {
        $cnt=0; $tot=0;
        foreach ($F as $row) foreach ($row as $v) { $tot++; if (is_finite($v)) $cnt++; }
        return [$cnt,$tot];
    }

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

    private function toFloat($v): float { if ($v === null) return NAN; if (is_numeric($v)) return (float)$v; return NAN; }

    private function hodAt(array $HOD, int $hour, int $y, int $x): float {
        $slice = $HOD[$hour] ?? null;
        $row = (is_array($slice)?($slice[$y] ?? null):null);
        if (!is_array($row)) return NAN;
        return $this->toFloat($row[$x] ?? null);
    }

    /** grid/pixel helpers */
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

    /* ======================== Meteo (Wind & BLH) ======================== */

    private function loadMeteoForHour(int $t)
    {
        $base = storage_path('app/weather/meteo/json');
        $indexPath = "{$base}/index.json";
        $idx = $this->readJsonSimple($indexPath);
        if (!is_array($idx)) return null;

        $run = $idx['latest_run'] ?? ($idx['cycle'] ?? null);
        if (!is_string($run) || $run==='') return null;

        // Prefer exactly +t, otherwise try (t..1)
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

    /* ======================== JSON readers ======================== */

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
                // guard against very large files
                if (strlen($buf) > 600 * 1024 * 1024) { gzclose($fp); return null; }
            }
            gzclose($fp);
            return $buf;
        }
        return null;
    }

    /* ======================== Stations IO & math (parity) ======================== */

    private function stationDirFor(string $product): string {
        return $product === 'o3tot' ? 'o3' : $product; // no2->no2 , o3tot->o3
    }

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

        // Case 4: NDJSON or CSV parsed into array of dicts: ['_ndjson'=>[...]]
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

    private function fastDistanceKm(float $lat1, float $lon1, float $lat2, float $lon2, float $cosLat1): float
    {
        $dlat = ($lat2 - $lat1);
        $dlon = ($lon2 - $lon1);
        $dx = 111.32 * $dlon * $cosLat1;
        $dy = 111.32 * $dlat;
        return sqrt($dx*$dx + $dy*$dy);
    }

    /**
     * Try to parse NDJSON lines or CSV (first row headers) into array of dicts: ['_ndjson'=>[...]].
     * CSV fix: map header names to values (rather than numeric keys).
     */
    private function tryParseNdjsonOrCsv(string $text) {
        $text = trim($text);
        if ($text==='') return null;
        $lines = preg_split("/\r\n|\n|\r/", $text);
        $items = [];
        $headers = null;

        foreach ($lines as $i=>$ln) {
            $ln = trim($ln);
            if ($ln==='') continue;

            // NDJSON line (simple heuristic)
            if ($ln[0]==='{' && substr($ln,-1)==='}') {
                $js = json_decode($ln, true);
                if (is_array($js)) { $items[] = $js; continue; }
            }

            // CSV
            if ($i===0 && strpos($ln, ',')!==false) {
                $headers = array_map(fn($h)=>trim($h, " \t\n\r\0\x0B\"'"), explode(',', $ln));
                continue;
            }
            if ($headers !== null) {
                $cols = array_map(fn($c)=>trim($c, " \t\n\r\0\x0B\"'"), explode(',', $ln));
                $row = [];
                foreach ($headers as $k=>$h) {
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
