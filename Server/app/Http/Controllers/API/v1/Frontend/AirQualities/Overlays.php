<?php

namespace App\Http\Controllers\API\V1\Frontend\AirQualities;

use Illuminate\Http\Request;

/**
 * Overlay renderer (PNG) from per-granule JSON and index.json
 * Output: image/png (200/304) or JSON error (4xx/5xx).
 *
 * Query params:
 * - product:  no2 | hcho | o3tot | cldo4
 * - v (or gid): granule id key (must exist in index.json and be within 72h window)
 * - z:         3..8 (low-zoom PNGs); >=9 is *not* in scope of Step-1 (JSON in Step-3)
 * - palette:   optional (viridis | gray)
 * - domain:    'auto' (default) or 'fixed:min,max'
 * - nocache:   if '1', bypasses file cache
 *
 * Response headers:
 * - X-Product, X-Unit, X-Domain-Min, X-Domain-Max, X-Palette, X-Domain-Strategy
 * - ETag / Last-Modified / Cache-Control
 */
class Overlays
{
    // Fixed North America viewport; client must use the same bounds.
    private const NA_S = 15.0, NA_N = 75.0, NA_W = -170.0, NA_E = -50.0;

    // Max data age (hours) for a gid to be considered valid (Step-1: past 72h only)
    private const MAX_AGE_HOURS = 72;

    public function build(Request $request)
    {
        /* -------- Parse & validate basic params -------- */
        $product = strtolower((string)$request->query('product', 'no2'));
        $allowed = ['no2','hcho','o3tot','cldo4'];
        if (!in_array($product, $allowed, true)) {
            return response()->json(['succeed'=>false,'status'=>400,'message'=>"Invalid product. Must be one of: no2 | hcho | o3tot | cldo4"], 400);
        }

        $z = (int)$request->query('z', 3);
        if ($z < 3 || $z > 8) {
            return response()->json(['succeed'=>false,'status'=>400,'message'=>"Step-1 supports only z=3..8."], 400);
        }

        $gid = (string)($request->query('v') ?? $request->query('gid') ?? '');
        if ($gid === '') {
            return response()->json(['succeed'=>false,'status'=>400,'message'=>"Parameter v (or gid) is required."], 400);
        }

        $paletteParam = strtolower((string)$request->query('palette', ''));
        $domainParam  = (string)$request->query('domain', 'auto'); // auto | fixed:min,max
        $noCacheFlag  = (string)$request->query('nocache', '0') === '1';

        /* -------- Load index.json and find gid -------- */
        $indexPath = storage_path("app/tempo/{$product}/json/index.json");
        if (!is_file($indexPath)) {
            return response()->json(['succeed'=>false,'status'=>404,'message'=>"index.json not found for '{$product}'."], 404);
        }
        $idx = $this->readJsonFileSafely($indexPath);
        if (!is_array($idx) || empty($idx)) {
            return response()->json(['succeed'=>false,'status'=>404,'message'=>"index.json is empty/invalid."], 404);
        }
        if (!isset($idx[$gid]) || !is_array($idx[$gid])) {
            return response()->json(['succeed'=>false,'status'=>404,'message'=>"gid not found in index.json.",'gid'=>$gid], 404);
        }

        $meta = $idx[$gid];

        // Enforce 72h recency window (either by 'end' or 't1'; fallback to 'saved')
        $now = time();
        $endIso = (string)($meta['end'] ?? $meta['t1'] ?? '');
        $endTs  = $this->parseIsoToTs($endIso);
        if (!$endTs && isset($meta['saved'])) {
            $endTs = $this->parseIsoToTs((string)$meta['saved']); // conservative fallback
        }
        if ($endTs) {
            $ageHours = ($now - $endTs) / 3600.0;
            if ($ageHours > self::MAX_AGE_HOURS) {
                return response()->json([
                    'succeed'=>false,'status'=>410,
                    'message'=>"gid is outside the last 72 hours window.",
                    'gid'=>$gid,'age_hours'=>round($ageHours,1)
                ], 410);
            }
        }

        // Resolve granule JSON path
        $file = (string)($meta['file'] ?? '');
        if ($file === '') {
            return response()->json(['succeed'=>false,'status'=>404,'message'=>"Invalid file for gid.", 'gid'=>$gid], 404);
        }
        $granulePath = storage_path("app/tempo/{$product}/json/{$file}");
        if (!is_file($granulePath)) {
            // Alt path if 'file' in index is already relative to storage/app
            $alt = storage_path("app/{$file}");
            if (is_file($alt)) $granulePath = $alt;
        }
        if (!is_file($granulePath)) {
            return response()->json(['succeed'=>false,'status'=>404,'message'=>"Granule JSON file not found.", 'file'=>$file], 404);
        }

        $g = $this->readJsonFileSafely($granulePath);
        if (!is_array($g) || empty($g['data']) || empty($g['shape']) || empty($g['bbox'])) {
            return response()->json(['succeed'=>false,'status'=>422,'message'=>"Granule JSON structure is incomplete."], 422);
        }
        [$rows,$cols] = $this->normalizeShape($g['shape']);
        if ($rows<=0 || $cols<=0) {
            return response()->json(['succeed'=>false,'status'=>422,'message'=>"Invalid shape."], 422);
        }
        $bbox = $g['bbox']; // [S,N,W,E]
        if (!is_array($bbox) || count($bbox)<4) {
            return response()->json(['succeed'=>false,'status'=>422,'message'=>"Invalid bbox."], 422);
        }
        $S = (float)$bbox[0]; $N=(float)$bbox[1]; $W=(float)$bbox[2]; $E=(float)$bbox[3];

        /* -------- Domain & palette -------- */
        $spec = $this->productSpec($product);
        $paletteName = $paletteParam !== '' ? $paletteParam : ($spec['palette'] ?? 'viridis');

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
                        return response()->json(['succeed'=>false,'status'=>400,'message'=>"domain=fixed:min,max is invalid."], 400);
                    }
                    $domainStrategy = 'fixed';
                }
            }
        }

        /* -------- File cache key & headers (vary by zoom) -------- */
        $srcMTime  = @filemtime($granulePath) ?: time();
        $srcSize   = @filesize($granulePath) ?: 0;

        // PNG output size by zoom
        [$OUT_W, $OUT_H] = $this->sizeForZoom($z);

        // Cache lifetimes by zoom
        $maxAge = $this->cacheMaxAgeForZoom($z); // seconds

        // Cache file path (keep 'tiles' to stay compatible with cleanup_tiles.sh)
        $domKey = $domainStrategy==='fixed' ? sprintf('%.6g-%.6g',$domainMin,$domainMax) : 'auto';
        $cacheKey  = implode('__', [$product, $gid, "z{$z}", "pal:{$paletteName}", "dom:{$domKey}"]);
        $cacheDir  = storage_path("app/tempo/{$product}/tiles/z{$z}");
        $cacheFile = "{$cacheDir}/{$cacheKey}.png";

        // Serve from cache if fresh enough and nocache is not requested
        if (!$noCacheFlag && is_file($cacheFile) && (@filemtime($cacheFile) >= $srcMTime)) {
            $etag = $this->makeEtag($product, $gid, $z, $paletteName, $domKey, $srcMTime, $srcSize);
            $resp = $this->streamPngFile($cacheFile, $etag, $srcMTime, [
                'X-Product'         => $product,
                'X-Unit'            => $spec['units'],
                'X-Domain-Min'      => (string)($domainMin ?? ''),
                'X-Domain-Max'      => (string)($domainMax ?? ''),
                'X-Palette'         => $paletteName,
                'X-Domain-Strategy' => $domainStrategy,
                'Cache-Control'     => "public, max-age={$maxAge}, s-maxage={$maxAge}",
            ]);
            if ($resp) return $resp;
        }

        /* -------- Rendering -------- */
        if (!function_exists('imagecreatetruecolor')) {
            return response()->json(['succeed'=>false,'status'=>500,'message'=>"GD extension is not enabled (php-gd)."], 500);
        }

        $im = imagecreatetruecolor($OUT_W, $OUT_H);
        imagealphablending($im, false);
        imagesavealpha($im, true);
        $transparent = imagecolorallocatealpha($im, 0, 0, 0, 127);
        imagefilledrectangle($im, 0, 0, $OUT_W-1, $OUT_H-1, $transparent);

        // Coordinate mappers (lon/lat -> pixel)
        $toX = function ($lon) use ($OUT_W) {
            if ($lon < self::NA_W || $lon > self::NA_E) return null;
            $t = ($lon - self::NA_W) / (self::NA_E - self::NA_W);
            return (int)round($t * ($OUT_W - 1));
        };
        $toY = function ($lat) use ($OUT_H) {
            if ($lat < self::NA_S || $lat > self::NA_N) return null;
            $t = (self::NA_N - $lat) / (self::NA_N - self::NA_S);
            return (int)round($t * ($OUT_H - 1));
        };

        // Input grid
        $data = $g['data']; // 2D [rows][cols]
        $dLat = ($N - $S) / $rows;
        $dLon = ($E - $W) / $cols;
        $halfLat = 0.5 * $dLat;
        $halfLon = 0.5 * $dLon;

        // Domain (auto if not fixed)
        if ($domainStrategy === 'auto') {
            [$domainMin, $domainMax] = $this->estimateDomainAuto($data, (float)$spec['cap'], $spec['qLow'], $spec['qHigh'], (bool)$spec['allowZero']);
        }

        // Palette & alpha
        $palette = $this->buildPalette($paletteName ?: ($spec['palette'] ?? 'viridis'));
        $nBins   = count($palette);
        $alphaBins = $this->lowBinAlphaProfile($nBins);

        $binColors = [];
        foreach ($palette as $i => $hex) {
            [$r,$g2,$b] = $this->hexToRgb($hex);
            $a = $alphaBins[$i] ?? 0;
            $binColors[$i] = imagecolorallocatealpha($im, $r, $g2, $b, $a);
        }

        // Paint cells
        $painted = 0;
        for ($iy=0; $iy<$rows; $iy++) {
            $latC = $S + ($iy + 0.5) * $dLat;
            $y0 = $toY($latC + $halfLat);
            $y1 = $toY($latC - $halfLat);
            if ($y0 === null && $y1 === null) continue;
            if ($y0 !== null && $y1 !== null && $y0 > $y1) { $tmp = $y0; $y0 = $y1; $y1 = $tmp; }
            $y0 = max(0, min($OUT_H-1, $y0 ?? 0));
            $y1 = max(0, min($OUT_H-1, $y1 ?? 0));

            $row = $data[$iy] ?? null;
            if (!is_array($row)) continue;

            for ($ix=0; $ix<$cols; $ix++) {
                $v = $row[$ix] ?? null;
                if (!$this->isNumber($v)) continue;
                $v = (float)$v;

                // Skip non-positive for non-cloud products
                if (!$spec['allowZero'] && $v <= 0.0) continue;

                // Normalize to [0,1]
                $t = ($v - $domainMin) / max(1e-12, ($domainMax - $domainMin));
                if ($t < 0) $t = 0; if ($t > 1) $t = 1;
                $bin = (int)floor($t * (max(1,$nBins)-1));
                if ($bin < 0) $bin = 0; if ($bin >= $nBins) $bin = $nBins-1;

                $col = $binColors[$bin];

                $lonC = $W + ($ix + 0.5) * $dLon;
                $x0 = $toX($lonC - $halfLon);
                $x1 = $toX($lonC + $halfLon);

                if ($x0 === null && $x1 === null) continue;
                if ($x0 !== null && $x1 !== null && $x0 > $x1) { $t2=$x0; $x0=$x1; $x1=$t2; }
                $x0 = max(0, min($OUT_W-1, $x0 ?? 0));
                $x1 = max(0, min($OUT_W-1, $x1 ?? 0));

                if ($x1 >= $x0 && $y1 >= $y0) {
                    imagefilledrectangle($im, $x0, $y0, $x1, $y1, $col);
                    $painted += ( ($x1-$x0+1) * ($y1-$y0+1) );
                }
            }
        }

        // Write/update cache file if allowed
        if (!$noCacheFlag) {
            if (!is_dir($cacheDir)) @mkdir($cacheDir, 0775, true);
            @imagepng($im, $cacheFile, 6, PNG_ALL_FILTERS);
            @touch($cacheFile, time());
        }

        // Compose response
        ob_start();
        imagepng($im);
        $png = ob_get_clean();
        imagedestroy($im);

        $etag = $this->makeEtag($product, $gid, $z, $paletteName, $domKey, $srcMTime, $srcSize);

        $headers = [
            'Content-Type'      => 'image/png',
            'ETag'              => $etag,
            'Last-Modified'     => gmdate('D, d M Y H:i:s \G\M\T', $srcMTime),
            'Cache-Control'     => "public, max-age={$maxAge}, s-maxage={$maxAge}",
            'X-Product'         => $product,
            'X-Unit'            => $spec['units'],
            'X-Domain-Min'      => (string)$domainMin,
            'X-Domain-Max'      => (string)$domainMax,
            'X-Palette'         => $paletteName,
            'X-Domain-Strategy' => $domainStrategy,
        ];

        // 304 handling
        $reqEtags = (string)($_SERVER['HTTP_IF_NONE_MATCH'] ?? '');
        if ($reqEtags !== '' && strpos($reqEtags, $etag) !== false) {
            return response('', 304, $headers);
        }

        return response($png, 200, $headers);
    }

    /* ===================== Helpers ===================== */

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

    private function normalizeShape($shape): array
    {
        if (is_array($shape) && count($shape)>=2) {
            $rows = (int)$shape[0];
            $cols = (int)$shape[1];
            return [$rows,$cols];
        }
        return [0,0];
    }

    private function isNumber($v): bool
    {
        return is_numeric($v) && is_finite((float)$v);
    }

    private function parseIsoToTs(?string $iso): ?int
    {
        if (!$iso) return null;
        $ts = @strtotime($iso);
        return $ts ? (int)$ts : null;
    }

    private function sizeForZoom(int $z): array
    {
        // Output width/height by zoom for Step-1
        switch ($z) {
            case 3:  return [384, 192];
            case 4:  return [512, 256];
            case 5:  return [512, 256];      // compact, low-cost
            case 6:  return [1024, 512];     // crisper
            case 7:  return [1280, 640];     // mid-high
            case 8:  return [1536, 768];     // highest in Step-1
            default: return [384, 192];
        }
    }

    private function cacheMaxAgeForZoom(int $z): int
    {
        // z=3..4 → 15m ; z=5..6 → 10m ; z=7..8 → 5m
        if ($z <= 4) return 15 * 60;
        if ($z <= 6) return 10 * 60;
        return 5 * 60;
    }

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
                    'allowZero' => true, // zero is valid
                ];
        }
        // fallback
        return [
            'units'     => '',
            'cap'       => 1.0,
            'qLow'      => 0.10,
            'qHigh'     => 0.98,
            'palette'   => 'viridis',
            'allowZero' => false,
        ];
    }

    private function estimateDomainAuto($data, float $cap, float $qLow, float $qHigh, bool $allowZero): array
    {
        $qLow  = max(0.0, min(0.49, $qLow));
        $qHigh = max($qLow+0.01, min(0.999, $qHigh));

        $vals = [];
        if (is_array($data)) {
            if (is_array(reset($data))) {
                foreach ($data as $row) {
                    if (!is_array($row)) continue;
                    foreach ($row as $v) {
                        if (!$this->isNumber($v)) continue;
                        $v = (float)$v;
                        if (!$allowZero && $v <= 0.0) continue;
                        $vals[] = $v;
                    }
                }
            } else {
                foreach ($data as $v) {
                    if (!$this->isNumber($v)) continue;
                    $v = (float)$v;
                    if (!$allowZero && $v <= 0.0) continue;
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
        $U = max($L+1e-9, min($cap, $vals[$pU]));
        return [$L, $U];
    }

    private function buildPalette(string $name): array
    {
        $name = strtolower($name);
        if ($name === 'gray' || $name === 'greys' || $name === 'cldo4gray') {
            // 16-step grayscale (dark -> light)
            return [
                '#0a0a0a','#1a1a1a','#2a2a2a','#3a3a3a',
                '#4a4a4a','#5a5a5a','#6a6a6a','#7a7a7a',
                '#8a8a8a','#9a9a9a','#aaaaaa','#bababa',
                '#cacaca','#dadada','#eaeaea','#f5f5f5',
            ];
        }
        // default: viridis-like 16 colors (compact and fast)
        return [
            '#440154','#481467','#482878','#3e4a89',
            '#31688e','#26828e','#1f9e89','#22a884',
            '#44bf70','#73d055','#95d840','#b8de29',
            '#dfe318','#f4e61e','#f9e721','#fde725',
        ];
    }

    private function lowBinAlphaProfile(int $n): array
    {
        // More transparency at lower bins to keep basemap readable
        $a = array_fill(0, $n, 0);
        if ($n>0) $a[0]=112; if ($n>1) $a[1]=96; if ($n>2) $a[2]=64;
        return $a;
    }

    private function hexToRgb(string $hex): array
    {
        $hex = ltrim($hex, '#');
        return [hexdec(substr($hex,0,2)), hexdec(substr($hex,2,2)), hexdec(substr($hex,4,2))];
    }

    private function makeEtag(string $product, string $gid, int $z, string $palette, string $domKey, int $srcMTime, int $srcSize): string
    {
        return 'W/"'.md5(implode('|', [$product,$gid,$z,$palette,$domKey,$srcMTime,$srcSize])).'"';
    }

    private function streamPngFile(string $path, string $etag, int $srcMTime, array $extraHeaders = [])
    {
        $reqEtags = (string)($_SERVER['HTTP_IF_NONE_MATCH'] ?? '');
        $headers = array_merge([
            'Content-Type'  => 'image/png',
            'ETag'          => $etag,
            'Last-Modified' => gmdate('D, d M Y H:i:s \G\M\T', $srcMTime),
        ], $extraHeaders);

        if ($reqEtags !== '' && strpos($reqEtags, $etag) !== false) {
            return response('', 304, $headers);
        }

        $bin = @file_get_contents($path);
        if ($bin === false) return null;
        return response($bin, 200, $headers);
    }
}
