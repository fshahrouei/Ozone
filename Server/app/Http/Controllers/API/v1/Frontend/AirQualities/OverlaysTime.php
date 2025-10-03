<?php

namespace App\Http\Controllers\API\V1\Frontend\AirQualities;

use Illuminate\Http\Request;

/**
 * OverlaysTime
 *
 * Returns a timeline (list of frames) for a given product from
 * storage/app/tempo/{product}/json/index.json with HTTP caching.
 *
 * Endpoint:
 *   GET /api/v1/frontend/air-quality/times?product=no2&days=3&order=asc
 *
 * Query params:
 * - product:   no2 | hcho | o3tot | cldo4   (required)
 * - days:      integer window in days (default: 3)
 * - order:     asc | desc (default: asc)
 *
 * Response JSON (200):
 * {
 *   "succeed": true,
 *   "status": 200,
 *   "product": "no2",
 *   "units": "molec/cm²",
 *   "latest": { "gid":"...", "start":"ISO", "end":"ISO" } | null,
 *   "times": [
 *      { "gid":"...", "start":"ISO", "end":"ISO" },
 *      ...
 *   ]
 * }
 *
 * Headers:
 * - ETag / Last-Modified / Cache-Control: public, max-age=600, s-maxage=600
 *   Supports 304 via If-None-Match.
 */
class OverlaysTime
{
    public function build(Request $request)
    {
        // --- Validate product
        $product = strtolower((string)$request->query('product', ''));
        $allowed = ['no2', 'hcho', 'o3tot', 'cldo4'];
        if (!in_array($product, $allowed, true)) {
            return response()->json([
                'succeed' => false,
                'status'  => 400,
                'message' => "Invalid product. Must be one of: no2 | hcho | o3tot | cldo4",
            ], 400);
        }

        // --- Days window (soft clamp to avoid huge payloads)
        $days = (int)$request->query('days', 3);
        if ($days <= 0) $days = 3;
        $days = max(1, min(168, $days)); // up to 168 days (~24 weeks) if ever needed

        // --- Sort order
        $order = strtolower((string)$request->query('order', 'asc'));
        if (!in_array($order, ['asc', 'desc'], true)) $order = 'asc';

        // --- Load index.json
        $indexPath = storage_path("app/tempo/{$product}/json/index.json");
        if (!is_file($indexPath)) {
            return response()->json([
                'succeed' => false,
                'status'  => 404,
                'message' => "index.json was not found for '{$product}'.",
            ], 404);
        }

        $idx = $this->readJsonFileSafely($indexPath);
        if (!is_array($idx) || empty($idx)) {
            return response()->json([
                'succeed' => false,
                'status'  => 404,
                'message' => "index.json is empty/invalid.",
            ], 404);
        }

        $nowUtc     = time();
        $cutoffUtc  = $nowUtc - ($days * 86400);

        $rows = [];
        $latest = null;
        $latestEpoch = null;

        // index shape: { gid: { t0: ISO, t1: ISO, file: "...", ... }, ... }
        foreach ($idx as $gid => $meta) {
            if (!is_array($meta)) continue;

            $t0 = isset($meta['t0']) ? (string)$meta['t0'] : (string)($meta['start'] ?? '');
            $t1 = isset($meta['t1']) ? (string)$meta['t1'] : (string)($meta['end'] ?? '');

            $e0 = $this->toEpoch($t0);
            $e1 = $this->toEpoch($t1);

            // Skip if both timestamps are missing
            if ($e0 === null && $e1 === null) continue;

            // Choose end as primary time; fallback to start
            $e = $e1 ?? $e0 ?? null;
            if ($e === null) continue;

            // Filter by cutoff window
            if ($e < $cutoffUtc) continue;

            $rows[] = [
                'gid'   => (string)$gid,
                'start' => $t0 ?: null,
                'end'   => $t1 ?: null,
                '_e'    => $e, // internal sort key
            ];

            // Track latest frame
            if ($latestEpoch === null || $e > $latestEpoch) {
                $latestEpoch = $e;
                $latest = [
                    'gid'   => (string)$gid,
                    'start' => $t0 ?: null,
                    'end'   => $t1 ?: null,
                ];
            }
        }

        // --- Sort by requested order
        usort($rows, function ($a, $b) use ($order) {
            if ($a['_e'] === $b['_e']) return 0;
            if ($order === 'asc') {
                return ($a['_e'] < $b['_e']) ? -1 : 1;
            }
            return ($a['_e'] > $b['_e']) ? -1 : 1;
        });

        // --- Strip internal keys
        foreach ($rows as &$r) { unset($r['_e']); }

        $spec   = $this->productSpec($product);
        $units  = $spec['units'];

        // --- Caching headers
        $idxMTime = @filemtime($indexPath) ?: $nowUtc;
        $idxSize  = @filesize($indexPath) ?: 0;
        $etag = $this->makeEtagTimeline($product, $days, $order, $idxMTime, $idxSize, $latestEpoch, count($rows));

        // If-None-Match → 304
        $reqEtags = (string)($_SERVER['HTTP_IF_NONE_MATCH'] ?? '');
        $headers = [
            'Content-Type'  => 'application/json; charset=utf-8',
            'ETag'          => $etag,
            'Last-Modified' => gmdate('D, d M Y H:i:s \G\M\T', max($idxMTime, $latestEpoch ?? $idxMTime)),
            'Cache-Control' => 'public, max-age=600, s-maxage=600',
        ];

        if ($reqEtags !== '' && strpos($reqEtags, $etag) !== false) {
            return response('', 304, $headers);
        }

        // --- Payload
        $body = [
            'succeed' => true,
            'status'  => 200,
            'product' => $product,
            'units'   => $units,
            'latest'  => $latest,
            'times'   => $rows,
        ];

        return response()->json($body, 200, $headers);
    }

    /* ===================== Helpers ===================== */

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

    private function toEpoch(?string $iso): ?int
    {
        if (!$iso) return null;
        $t = strtotime($iso);
        return $t !== false ? $t : null;
    }

    private function makeEtagTimeline(string $product, int $days, string $order, int $idxMTime, int $idxSize, ?int $latestEpoch, int $count): string
    {
        return 'W/"' . md5(implode('|', [
            'overlay-times',
            $product, $days, $order,
            $idxMTime, $idxSize,
            (string)($latestEpoch ?? 0),
            $count
        ])) . '"';
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
