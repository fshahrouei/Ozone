<?php

namespace App\Http\Controllers\API\V1\Frontend\AirQualities;

use Illuminate\Http\Request;

/**
 * OverlaysLegend
 *
 * GET /api/v1/frontend/air-quality/legend?product=no2
 *
 * Sample response:
 * {
 *   "succeed": true,
 *   "status": 200,
 *   "product": "no2",
 *   "units": "molec/cm²",
 *   "palette": "viridis",
 *   "stops":  [0, 0.2, 0.4, 0.6, 0.8, 1],
 *   "values": [1.0e15, 2.5e15, 4.0e15, 6.0e15, 8.0e15, 1.2e16],
 *   "labels": ["1e15","2.5e15","4e15","6e15","8e15","1.2e16"],
 *   "colors": ["#440154","#3B528B","#21908C","#5DC962","#FDE725","#FDFEBD"], // The last entry can be an optional highlight
 *   "message": null
 * }
 *
 * Notes:
 * - Caching: ETag + Cache-Control: public, max-age=21600 (6h)
 * - Disable cache with ?nocache=1
 * - Palettes: viridis (for no2/hcho/o3tot) and gray (for cldo4)
 */
class OverlaysLegend
{
    public function build(Request $request)
    {
        // ---- 1) Input & validation
        $product = strtolower((string)$request->query('product', 'no2'));
        $allowed = ['no2','hcho','o3tot','cldo4'];
        if (!in_array($product, $allowed, true)) {
            // Fallback to 'no2' instead of 400 (keeps menu UX simple)
            $product = 'no2';
        }

        // ---- 2) Product spec (mirrors server-side productSpec)
        $spec    = $this->productSpec($product);
        $units   = (string)$spec['units'];
        $cap     = (float)$spec['cap'];
        $palette = (string)$spec['palette']; // viridis | gray

        // ---- 3) Generate ticks/labels (6 ticks)
        [$values, $labels] = $this->makeTicks($product, $units, $cap);

        // Normalized stops (0..1), same length as labels
        $n = max(2, count($labels));
        $stops = [];
        for ($i = 0; $i < $n; $i++) {
            $stops[] = $n > 1 ? $i / ($n - 1) : 0.0;
        }

        // ---- 4) Colors from palette
        $colors = $this->paletteColors($palette, $n);

        // ---- 5) ETag/Cache headers
        $nocache = (string)$request->query('nocache', '') !== '';
        $etag = 'W/"'.md5(implode('|', ['legend',$product,$units,$palette,implode(',',$labels)])).'"';

        $headers = [
            'Content-Type'  => 'application/json; charset=utf-8',
            'ETag'          => $etag,
            'Cache-Control' => $nocache ? 'no-store, no-cache, must-revalidate' : 'public, max-age=21600, s-maxage=21600', // 6h
        ];

        if (!$nocache) {
            $ifNoneMatch = (string)($_SERVER['HTTP_IF_NONE_MATCH'] ?? '');
            if ($ifNoneMatch !== '' && strpos($ifNoneMatch, $etag) !== false) {
                return response('', 304, $headers);
            }
        }

        // ---- 6) Response body
        $body = [
            'succeed' => true,
            'status'  => 200,
            'product' => $product,
            'units'   => $units,
            'palette' => $palette,
            'stops'   => $stops,
            'values'  => $values,   // numeric values
            'labels'  => $labels,   // display strings
            'colors'  => $colors,   // hex colors
            'message' => null,
        ];

        return response()->json($body, 200, $headers);
    }

    /* ===================== Helpers ===================== */

    private function makeTicks(string $product, string $units, float $cap): array
    {
        // Target: 6 ticks
        $n = 6;

        // Products with simple fixed rules:
        if ($product === 'cldo4') {
            // Cloud fraction 0..1 → 0, 0.2, ... , 1.0
            $vals = [];
            for ($i=0; $i<$n; $i++) { $vals[] = round($i * (1.0/($n-1)), 2); }
            $labels = array_map(function($v){ return rtrim(rtrim(number_format($v,2,'.',''), '0'), '.'); }, $vals);
            return [$vals, $labels];
        }

        if ($product === 'o3tot' && $units === 'DU') {
            // Total ozone (Dobson Units) → a readable range ~200..cap
            $min = 200.0;
            $max = max($min, $cap); // cap≈700
            [$vals, $labels] = $this->niceTicks($min, $max, $n, 0);
            return [$vals, $labels];
        }

        // no2 / hcho (molec/cm²): nice scientific labels around cap
        if ($units === 'molec/cm²') {
            // Example tuned for cap≈1.2e16:
            // [1e15, 2.5e15, 4e15, 6e15, 8e15, 1.2e16]
            $vals = [
                $cap * 1e-1 * 0.8333, // ≈ 1.0e15 when cap=1.2e16
                $cap * 1e-1 * 2.0833, // ≈ 2.5e15
                $cap * 1e-1 * 3.3333, // ≈ 4.0e15
                $cap * 1e-1 * 5.0000, // ≈ 6.0e15
                $cap * 1e-1 * 6.6667, // ≈ 8.0e15
                $cap,                 // cap
            ];
            $vals = array_map(function($v){ return $this->roundSig($v, 2); }, $vals);
            $labels = array_map([$this,'sciLabel'], $vals);
            return [$vals, $labels];
        }

        // Generic fallback: nice ticks from 0..cap
        return $this->niceTicks(0.0, $cap, $n, 2);
    }

    private function niceTicks(float $min, float $max, int $n, int $decimals = 0): array
    {
        if ($max <= $min) $max = $min + 1.0;
        $rawStep = ($max - $min) / max(1, $n - 1);
        $mag = pow(10, floor(log10($rawStep)));
        $norm = $rawStep / $mag; // 1..10
        if ($norm < 1.5)      $step = 1 * $mag;
        elseif ($norm < 3)    $step = 2 * $mag;
        elseif ($norm < 7)    $step = 5 * $mag;
        else                  $step = 10 * $mag;

        $start = ceil($min / $step) * $step;
        $vals = [];
        for ($i = 0; $i < $n; $i++) {
            $vals[] = $start + $i*$step;
        }
        // Ensure we cover max
        if (end($vals) < $max) {
            $vals[] = end($vals) + $step;
            $vals = array_slice($vals, 0, $n);
        }
        $labels = array_map(function($v) use ($decimals) {
            return number_format($v, $decimals, '.', '');
        }, $vals);
        return [$vals, $labels];
    }

    private function sciLabel(float $v): string
    {
        // Short scientific notation: 1e15, 2.5e15, 1.2e16 ...
        if ($v == 0.0) return '0';
        $exp = floor(log10(abs($v)));
        $mant = $v / pow(10, $exp);
        // Round mantissa
        $mant = $this->roundSig($mant, 2);
        // If mantissa ≈ 10 → shift to 1e(exp+1)
        if ($mant >= 10.0) { $mant = 1.0; $exp += 1; }
        // Drop trailing .0
        $mantStr = rtrim(rtrim(number_format($mant, 2, '.', ''), '0'), '.');
        return $mantStr . 'e' . (string)$exp;
    }

    private function roundSig(float $v, int $sig = 2): float
    {
        if ($v == 0.0) return 0.0;
        $exp = floor(log10(abs($v)));
        $factor = pow(10, $sig - 1 - $exp);
        return round($v * $factor) / $factor;
    }

    private function paletteColors(string $palette, int $n): array
    {
        // 6 (or 7) visually clear colors. If n differs, we linearly scale.
        $viridis6 = ['#440154','#3B528B','#21908C','#5DC962','#FDE725','#FDFEBD'];
        $gray6    = ['#000000','#2C2C2C','#595959','#858585','#B2B2B2','#E0E0E0'];

        $base = ($palette === 'gray') ? $gray6 : $viridis6;

        if ($n <= count($base)) {
            return array_slice($base, 0, $n);
        }

        // Linear interpolation if n > base count
        $out = [];
        for ($i=0; $i<$n; $i++) {
            $t = $n>1 ? $i/($n-1) : 0.0;
            $idx = $t*(count($base)-1);
            $i0 = (int)floor($idx);
            $i1 = min($i0+1, count($base)-1);
            $f  = $idx - $i0;
            $out[] = $this->lerpHex($base[$i0], $base[$i1], $f);
        }
        return $out;
    }

    private function lerpHex(string $c0, string $c1, float $t): string
    {
        $c0 = ltrim($c0, '#'); $c1 = ltrim($c1, '#');
        $r0 = hexdec(substr($c0,0,2)); $g0 = hexdec(substr($c0,2,2)); $b0 = hexdec(substr($c0,4,2));
        $r1 = hexdec(substr($c1,0,2)); $g1 = hexdec(substr($c1,2,2)); $b1 = hexdec(substr($c1,4,2));
        $r = (int)round($r0 + ($r1-$r0)*$t);
        $g = (int)round($g0 + ($g1-$g0)*$t);
        $b = (int)round($b0 + ($b1-$b0)*$t);
        return '#' . str_pad(dechex($r),2,'0',STR_PAD_LEFT)
                   . str_pad(dechex($g),2,'0',STR_PAD_LEFT)
                   . str_pad(dechex($b),2,'0',STR_PAD_LEFT);
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
}
