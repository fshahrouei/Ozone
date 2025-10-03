<?php

namespace App\Http\Controllers\API\V1\Frontend\AirQualities;

use Illuminate\Http\Request;

/**
 * overlay-grids — JSON grid for high zooms (past TEMPO, viewport subset)
 *
 * Endpoint: GET /api/v1/frontend/air-quality/overlay-grids
 * Output: application/json (200/304 on success; JSON error on 4xx/5xx)
 *
 * Query:
 * - product:  no2 | hcho | o3tot | cldo4           (required)
 * - z:        9..11                                (required; high-zoom JSON mode)
 * - t:        gid (e.g., G3703105776-LARC_CLOUD)   (required; must exist & be fresh)
 * - bbox:     "W,S,E,N" floats (viewport rect)     (required; will be clipped to NA and bucketed)
 * - domain:   auto | fixed:min,max                 (optional; default=auto)
 * - palette:  viridis | gray                       (optional; parity with legend; echoed in body)
 * - nocache:  0|1                                  (optional; default=0; bypass HTTP cache)
 *
 * Policy notes implemented here:
 * - Return BOTH requested bbox and effective bbox (clipped+bucketed) in body.
 * - Enforce cell-count caps by zoom: z=9→12k, z=10→20k, z=11→25k (400 if exceeded).
 * - Always return HTTP 200 with cells:[] when no cells found (not 404).
 * - Echo: crs=EPSG:4326, cell_anchor=centroid, bucket_deg, palette, cells_count.
 * - Clamp cloud (if present) to [0..1], include only finite numbers.
 * - CORS: Access-Control-Allow-Origin: * ; plus X-* headers parity with PNG overlays.
 */
class OverlayGrids
{
    /* ===== Fixed NA frame ===== */
    private const NA_S = 15.0, NA_N = 75.0, NA_W = -170.0, NA_E = -50.0;

    /* ===== Retention / cache ===== */
    private const MAX_AGE_HOURS   = 72;      // same as overlays
    private const BBOX_BUCKET_DEG = 0.1;     // granularity for cache bucketing
    private const CACHE_MAX_AGE_S = 300;     // 5 minutes for JSON grids

    public function build(Request $request)
    {
        /* ---------- 1) Parse & validate ---------- */
        $product = strtolower((string)$request->query('product', ''));
        $allowed = ['no2','hcho','o3tot','cldo4'];
        if (!in_array($product, $allowed, true)) {
            return $this->jerr(400, "Invalid product. Must be one of: no2 | hcho | o3tot | cldo4");
        }

        $z = (int)$request->query('z', 0);
        if ($z < 9 || $z > 11) {
            return $this->jerr(400, "overlay-grids supports only zoom levels 9..11. z={$z}");
        }

        $gid = trim((string)($request->query('t') ?? ''));
        if ($gid === '') {
            return $this->jerr(400, "Parameter t (granule id) is required.");
        }

        $bboxRawStr = (string)$request->query('bbox', '');
        $bboxReq = $this->parseBbox($bboxRawStr);
        if (!$bboxReq) {
            return $this->jerr(400, "Invalid bbox parameter. Format: W,S,E,N");
        }

        $domainParam = (string)$request->query('domain', 'auto'); // auto | fixed:min,max
        $paletteParam = strtolower((string)$request->query('palette', ''));
        $noCacheFlag  = (string)$request->query('nocache', '0') === '1';

        /* ---------- 2) Clip & bucket bbox ---------- */
        $bboxClipped = $this->clipToNA($bboxReq);
        if ($bboxClipped['e'] <= $bboxClipped['w'] || $bboxClipped['n'] <= $bboxClipped['s']) {
            return $this->jerr(400, "bbox became invalid after clipping (zero/negative area).");
        }
        [$bw,$bs,$be,$bn] = $this->bucketBbox([$bboxClipped['w'],$bboxClipped['s'],$bboxClipped['e'],$bboxClipped['n']], self::BBOX_BUCKET_DEG);
        $bboxEffective = ['w'=>$bw, 's'=>$bs, 'e'=>$be, 'n'=>$bn];

        /* ---------- 3) Load index.json & granule ---------- */
        $indexPath = storage_path("app/tempo/{$product}/json/index.json");
        if (!is_file($indexPath)) {
            return $this->jerr(404, "index.json not found for '{$product}'.");
        }
        $idx = $this->readJsonFileSafely($indexPath);
        if (!is_array($idx) || empty($idx)) {
            return $this->jerr(404, "index.json is empty/invalid.");
        }
        if (!isset($idx[$gid]) || !is_array($idx[$gid])) {
            return $this->jerr(404, "gid not found in index.json.", ['gid'=>$gid]);
        }
        $meta = $idx[$gid];

        // Recency (<=72h)
        $now = time();
        $endIso = (string)($meta['end'] ?? $meta['t1'] ?? '');
        $endTs  = $this->parseIsoToTs($endIso) ?? ($this->parseIsoToTs((string)($meta['saved'] ?? '')) ?? null);
        if ($endTs) {
            $ageHours = ($now - $endTs) / 3600.0;
            if ($ageHours > self::MAX_AGE_HOURS) {
                return $this->jerr(410, "gid is outside the last 72 hours window.", [
                    'gid'=>$gid,'age_hours'=>round($ageHours,1)
                ]);
            }
        }

        $file = (string)($meta['file'] ?? '');
        if ($file === '') {
            return $this->jerr(404, "Invalid file for gid.", ['gid'=>$gid]);
        }
        $granulePath = storage_path("app/tempo/{$product}/json/{$file}");
        if (!is_file($granulePath)) {
            $alt = storage_path("app/{$file}");
            if (is_file($alt)) $granulePath = $alt;
        }
        if (!is_file($granulePath)) {
            return $this->jerr(404, "Granule JSON file not found.", ['file'=>$file]);
        }

        $g = $this->readJsonFileSafely($granulePath);
        if (!is_array($g) || empty($g['data']) || empty($g['shape']) || empty($g['bbox'])) {
            return $this->jerr(422, "Granule JSON structure is incomplete.");
        }

        [$rows,$cols] = $this->normalizeShape($g['shape']);
        if ($rows<=0 || $cols<=0) {
            return $this->jerr(422, "Invalid shape.");
        }
        $gb = $g['bbox']; // [S,N,W,E]
        if (!is_array($gb) || count($gb)<4) {
            return $this->jerr(422, "Invalid granule bbox.");
        }
        $S=(float)$gb[0]; $N=(float)$gb[1]; $W=(float)$gb[2]; $E=(float)$gb[3];

        $srcMTime  = @filemtime($granulePath) ?: time();
        $srcSize   = @filesize($granulePath) ?: 0;

        $spec = $this->productSpec($product);
        $paletteName = $paletteParam !== '' ? $paletteParam : ($spec['palette'] ?? 'viridis');

        $domKey = $this->domainKey($domainParam);
        $etag = $this->makeEtag(
            $product, $z, $gid,
            $bboxEffective['w'], $bboxEffective['s'], $bboxEffective['e'], $bboxEffective['n'],
            $domKey, $paletteName, $srcMTime, $srcSize
        );

        /* ---------- 4) Early 304 (unless nocache) ---------- */
        if (!$noCacheFlag) {
            $reqEtags = (string)($_SERVER['HTTP_IF_NONE_MATCH'] ?? '');
            if ($reqEtags !== '' && strpos($reqEtags, $etag) !== false) {
                return response('', 304, [
                    'Content-Type'                  => 'application/json',
                    'ETag'                          => $etag,
                    'Last-Modified'                 => gmdate('D, d M Y H:i:s \G\M\T', $srcMTime),
                    'Cache-Control'                 => "public, max-age=".self::CACHE_MAX_AGE_S.", s-maxage=".self::CACHE_MAX_AGE_S,
                    'Access-Control-Allow-Origin'   => '*',
                    'X-Product'                     => $product,
                    'X-Unit'                        => $spec['units'] ?? '',
                    'X-Palette'                     => $paletteName,
                    'X-Domain-Strategy'             => (stripos($domainParam,'fixed:')===0?'fixed':'auto'),
                    'X-BBox-Clip'                   => $bboxEffective['w'].','.$bboxEffective['s'].','.$bboxEffective['e'].','.$bboxEffective['n'],
                    'X-Bucket-Deg'                  => (string)self::BBOX_BUCKET_DEG,
                ]);
            }
        }

        /* ---------- 5) Compute viewport subset ---------- */
        $dLat = ($N - $S) / $rows;
        $dLon = ($E - $W) / $cols;

        $rowIdx = $this->indexRangeForLat($bboxEffective['s'], $bboxEffective['n'], $S, $dLat, $rows);
        $colIdx = $this->indexRangeForLon($bboxEffective['w'], $bboxEffective['e'], $W, $dLon, $cols);

        $cells = [];
        $vals  = [];
        $cellsCount = 0;

        if ($rowIdx && $colIdx) {
            [$iy0,$iy1] = $rowIdx;  // inclusive
            [$ix0,$ix1] = $colIdx;  // inclusive

            $estCells = max(0, $iy1 - $iy0 + 1) * max(0, $ix1 - $ix0 + 1);
            $cap = $this->cellsCapForZoom($z);
            if ($estCells > $cap) {
                return $this->jerr(400, "bbox too large for given zoom.", ['cells_est'=>$estCells, 'cells_cap'=>$cap, 'z'=>$z]);
            }

            $allowZero = (bool)$spec['allowZero'];
            $data = $g['data']; // 2D array

            $hasCloud = isset($g['cloud']) && is_array($g['cloud']);
            $cloudArr = $hasCloud ? $g['cloud'] : null;

            for ($iy=$iy0; $iy<=$iy1; $iy++) {
                $latC = $S + ($iy + 0.5) * $dLat;
                for ($ix=$ix0; $ix<=$ix1; $ix++) {
                    $row = $data[$iy] ?? null;
                    if (!is_array($row)) continue;

                    $v = $row[$ix] ?? null;
                    if (!$this->isNumber($v)) continue;
                    $v = (float)$v;
                    if (!$allowZero && $v <= 0.0) continue;

                    $lonC = $W + ($ix + 0.5) * $dLon;
                    if ($lonC < $bboxEffective['w'] || $lonC > $bboxEffective['e'] || $latC < $bboxEffective['s'] || $latC > $bboxEffective['n']) {
                        continue; // center-in-viewport test
                    }

                    $vals[] = $v;

                    $cell = [
                        'lat'   => round($latC, 4),
                        'lon'   => round($lonC, 4),
                        'value' => $v,
                    ];

                    if ($hasCloud) {
                        $cv = $cloudArr[$iy][$ix] ?? null;
                        if ($this->isNumber($cv)) {
                            $cv = (float)$cv;
                            if (!is_finite($cv)) {
                                // skip
                            } else {
                                if ($cv < 0.0) $cv = 0.0;
                                if ($cv > 1.0) $cv = 1.0;
                                $cell['cloud'] = $cv;
                            }
                        }
                    }

                    $cells[] = $cell;
                    $cellsCount++;
                }
            }
        }

        // Domain resolution
        $domainStrategy = 'auto';
        $domainMin = null; $domainMax = null;

        if (stripos($domainParam, 'fixed:') === 0) {
            $parts = explode(':', $domainParam, 2);
            if (isset($parts[1])) {
                $nums = explode(',', $parts[1]);
                if (count($nums) === 2) {
                    $domainMin = (float)$nums[0];
                    $domainMax = (float)$nums[1];
                    if (!is_finite($domainMin) || !is_finite($domainMax) || $domainMax <= $domainMin) {
                        return $this->jerr(400, "domain=fixed:min,max is invalid.");
                    }
                    $domainStrategy = 'fixed';
                }
            }
        }

        if ($domainStrategy === 'auto') {
            [$domainMin, $domainMax] = $this->estimateDomainAuto(
                $vals, (float)$spec['cap'], $spec['qLow'], $spec['qHigh'], (bool)$spec['allowZero']
            );
        }

        $payload = [
            'succeed'       => true,
            'status'        => 200,
            'product'       => $product,
            'units'         => $spec['units'] ?? '',
            'mode'          => 'past',
            'z'             => $z,
            't'             => $gid,
            'crs'           => 'EPSG:4326',
            'cell_anchor'   => 'centroid',
            'palette'       => $paletteName,
            'bbox'          => [ 'w'=>$bboxReq['w'], 's'=>$bboxReq['s'], 'e'=>$bboxReq['e'], 'n'=>$bboxReq['n'] ],
            'bbox_effective'=> [ 'w'=>$bboxEffective['w'], 's'=>$bboxEffective['s'], 'e'=>$bboxEffective['e'], 'n'=>$bboxEffective['n'] ],
            'bucket_deg'    => self::BBOX_BUCKET_DEG,
            'grid_deg'      => $this->gridDeg($g, $dLat, $dLon),
            'domain'        => [
                'strategy' => $domainStrategy,
                'min'      => $domainMin,
                'max'      => $domainMax,
            ],
            'cells_count'   => $cellsCount,
            'cells'         => $cells,
        ];

        if ($cellsCount === 0) {
            $payload['hint'] = 'no cells in viewport; try a different gid or bbox';
        }

        return $this->jsucc($payload, $etag, $srcMTime, $product, $spec, $noCacheFlag);
    }

    /* ===================== Helpers ===================== */

    /** JSON success with headers + CORS + cache */
    private function jsucc(array $payload, string $etag, int $srcMTime, string $product, array $spec, bool $noCache)
    {
        $headers = [
            'Content-Type'                  => 'application/json',
            'ETag'                          => $etag,
            'Last-Modified'                 => gmdate('D, d M Y H:i:s \G\M\T', $srcMTime),
            'Access-Control-Allow-Origin'   => '*',
            'X-Product'                     => $product,
            'X-Unit'                        => $spec['units'] ?? '',
            'X-Domain-Min'                  => (string)($payload['domain']['min'] ?? ''),
            'X-Domain-Max'                  => (string)($payload['domain']['max'] ?? ''),
            'X-Domain-Strategy'             => (string)($payload['domain']['strategy'] ?? ''),
            'X-Palette'                     => (string)($payload['palette'] ?? ''),
            'X-BBox-Clip'                   => $payload['bbox_effective']['w'].','.$payload['bbox_effective']['s'].','.$payload['bbox_effective']['e'].','.$payload['bbox_effective']['n'],
            'X-Bucket-Deg'                  => (string)$payload['bucket_deg'],
            'X-Cells-Count'                 => (string)($payload['cells_count'] ?? 0),
        ];
        $headers['Cache-Control'] = $noCache ? 'no-store, max-age=0' : "public, max-age=".self::CACHE_MAX_AGE_S.", s-maxage=".self::CACHE_MAX_AGE_S;
        return response()->json($payload, 200, $headers, JSON_UNESCAPED_SLASHES);
    }

    /** JSON error helper */
    private function jerr(int $code, string $msg, array $details = null)
    {
        $body = ['succeed'=>false,'status'=>$code,'message'=>$msg];
        if ($details) $body['details'] = $details;
        return response()->json($body, $code, [
            'Content-Type'=>'application/json',
            'Access-Control-Allow-Origin' => '*',
        ], JSON_UNESCAPED_SLASHES);
    }

    private function readJsonFileSafely(string $path)
    {
        $raw = null;
        for ($try=0; $try<2; $try++) {
            $fh = @fopen($path, 'rb');
            if ($fh) {
                @flock($fh, LOCK_SH);
                $raw = @stream_get_contents($fh);
                @flock($fh, LOCK_UN);
                @fclose($fh);
            }
            if (is_string($raw) && $raw!=='') break;
            usleep(50000);
        }
        $js = json_decode((string)$raw, true);
        return is_array($js) ? $js : null;
    }

    private function parseIsoToTs(?string $iso): ?int
    {
        if (!$iso) return null;
        $ts = @strtotime($iso);
        return $ts ? (int)$ts : null;
    }

    private function normalizeShape($shape): array
    {
        if (is_array($shape) && count($shape)>=2) {
            return [(int)$shape[0], (int)$shape[1]];
        }
        return [0,0];
    }

    private function isNumber($v): bool
    {
        return is_numeric($v) && is_finite((float)$v);
    }

    private function parseBbox(string $s): ?array
    {
        $p = array_map('trim', explode(',', $s));
        if (count($p) !== 4) return null;
        $w = (float)$p[0]; $s_ = (float)$p[1]; $e = (float)$p[2]; $n = (float)$p[3];
        if ($e < $w) [$w,$e] = [$e,$w];
        if ($n < $s_) [$s_,$n] = [$n,$s_];
        return ['w'=>$w,'s'=>$s_,'e'=>$e,'n'=>$n];
    }

    private function clipToNA(array $b): array
    {
        $w = max(self::NA_W, min(self::NA_E, $b['w']));
        $e = max(self::NA_W, min(self::NA_E, $b['e']));
        $s = max(self::NA_S, min(self::NA_N, $b['s']));
        $n = max(self::NA_S, min(self::NA_N, $b['n']));
        if ($e < $w) [$w,$e] = [$e,$w];
        if ($n < $s) [$s,$n] = [$n,$s];
        return ['w'=>$w,'s'=>$s,'e'=>$e,'n'=>$n];
    }

    private function bucketBbox(array $b, float $deg): array
    {
        // b = [w,s,e,n]
        $w = floor($b[0]/$deg)*$deg;
        $s = floor($b[1]/$deg)*$deg;
        $e = ceil($b[2]/$deg)*$deg;
        $n = ceil($b[3]/$deg)*$deg;
        return [$w,$s,$e,$n];
    }

    private function domainKey(string $domainParam): string
    {
        if (stripos($domainParam,'fixed:')===0) {
            $parts = explode(':', $domainParam, 2);
            if (isset($parts[1])) {
                $nums = explode(',', $parts[1]);
                if (count($nums)===2) {
                    $a = (float)$nums[0]; $b = (float)$nums[1];
                    return 'fixed:'.sprintf('%.6g,%.6g',$a,$b);
                }
            }
        }
        return 'auto';
    }

    private function productSpec(string $product): array
    {
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
        return ['units'=>'','cap'=>1.0,'qLow'=>0.10,'qHigh'=>0.98,'palette'=>'viridis','allowZero'=>false];
    }

    private function estimateDomainAuto(array $vals, float $cap, float $qLow, float $qHigh, bool $allowZero): array
    {
        if (empty($vals)) return [0.0, $cap];
        sort($vals);
        $n = count($vals);
        $qLow  = max(0.0, min(0.49, $qLow));
        $qHigh = max($qLow+0.01, min(0.999, $qHigh));
        $pL = max(0, min($n-1, (int)floor($n*$qLow)));
        $pU = max(0, min($n-1, (int)ceil($n*$qHigh)));
        $L = max(0.0, min($cap, $vals[$pL]));
        $U = max($L+1e-9, min($cap, $vals[$pU]));
        return [$L, $U];
    }

    private function gridDeg(array $g, float $dLat, float $dLon): float
    {
        if (isset($g['grid_deg']) && is_numeric($g['grid_deg'])) {
            return (float)$g['grid_deg'];
        }
        return (float)min(abs($dLat), abs($dLon));
    }

    private function indexRangeForLat(float $s, float $n, float $S, float $dLat, int $rows): ?array
    {
        $iy0 = null; $iy1 = null;
        for ($iy=0; $iy<$rows; $iy++) {
            $latC = $S + ($iy + 0.5) * $dLat;
            if ($latC >= $s && $latC <= $n) {
                if ($iy0===null) $iy0=$iy;
                $iy1=$iy;
            }
        }
        return ($iy0===null) ? null : [$iy0,$iy1];
    }

    private function indexRangeForLon(float $w, float $e, float $W, float $dLon, int $cols): ?array
    {
        $ix0 = null; $ix1 = null;
        for ($ix=0; $ix<$cols; $ix++) {
            $lonC = $W + ($ix + 0.5) * $dLon;
            if ($lonC >= $w && $lonC <= $e) {
                if ($ix0===null) $ix0=$ix;
                $ix1=$ix;
            }
        }
        return ($ix0===null) ? null : [$ix0,$ix1];
    }

    private function cellsCapForZoom(int $z): int
    {
        if ($z <= 9)  return 12000;
        if ($z == 10) return 20000;
        return 25000; // z==11
    }

    private function makeEtag(string $product, int $z, string $gid, float $w, float $s, float $e, float $n, string $domKey, string $paletteName, int $srcMTime, int $srcSize): string
    {
        $key = implode('|', [
            $product, $z, $gid,
            sprintf('w%.3f,s%.3f,e%.3f,n%.3f',$w,$s,$e,$n),
            $domKey, $paletteName, $srcMTime, $srcSize
        ]);
        return 'W/"'.md5($key).'"';
    }
}
