<?php

namespace App\Http\Controllers\API\V1\Frontend;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Response;
use Illuminate\Support\Facades\Log;
use App\Http\Controllers\API\V1\Frontend\FrontendBaseController;
use App\Models\ClimateHealthAdvisor;

use Illuminate\Support\Facades\File;
use Symfony\Component\HttpFoundation\JsonResponse;
use Google\Auth\Credentials\ServiceAccountCredentials;
use GuzzleHttp\Client as GuzzleClient; // FCM HTTP v1 (to Google)
use App\Http\Controllers\API\V1\Frontend\AirQualitiesController;

/**
 * HealthAdvisorController
 *
 * REST endpoints for creating, listing, and deleting Health Advisor submissions
 * from the Flutter client. Also contains a debug endpoint to send a test FCM
 * notification populated with computed air-quality context (via point-assess).
 *
 * Notes:
 * - All comments/documentation are in English per request.
 * - No application logic has been changed; only comments were added/refined.
 */
class HealthAdvisorController extends FrontendBaseController
{
    public function __construct()
    {
        parent::__construct();
        // Controller-scoped meta used by base/frontend abstractions
        $this->var['model_type']          = 'health-advisor';
        $this->var['model_name']          = 'health-advisor';
        $this->var['model_api']           = 'health-advisor';
        $this->var['model_name_singular'] = 'health-advisor';
        $this->var['model_class']         = ClimateHealthAdvisor::class;
        $this->var['model_icon']          = '<i class="iconix icon-heartbeat"></i>';
        $this->var['model_view']          = $this->var['model_framework'] . '.frontend.' . $this->var['model_name'];
    }

    // ---------------------------------------------------------------------
    // GET /api/v1/frontend/health-advisor/index
    // List submissions with optional filters/pagination/sorting
    // ---------------------------------------------------------------------
    public function index(Request $request)
    {
        try {
            $q = ClimateHealthAdvisor::query();

            // Optional filters
            if ($uuid = $request->query('uuid')) {
                $q->where('uuid', trim((string)$uuid));
            }
            if ($request->boolean('has_location', false)) {
                $q->whereNotNull('location_lat')->whereNotNull('location_lon');
            }
            if ($search = $request->query('search')) {
                // Escape % to prevent wildcard injection
                $q->where('name', 'LIKE', '%' . str_replace('%', '\%', $search) . '%');
            }

            // Sorting (defaults to -received_at)
            $sort = (string) $request->query('sort', '-received_at');
            $dir  = str_starts_with($sort, '-') ? 'desc' : 'asc';
            $col  = ltrim($sort, '-');

            $allowed = ['received_at', 'created_at', 'name', 'overall_score'];
            if (!in_array($col, $allowed, true)) {
                $col = 'received_at';
                $dir = 'desc';
            }
            $q->orderBy($col, $dir);

            // Pagination (1..50 items per page)
            $perPage = (int) $request->query('per_page', 10);
            $perPage = max(1, min(50, $perPage));
            $page    = max(1, (int) $request->query('page', 1));

            $p = $q->paginate($perPage, ['*'], 'page', $page);

            // Map Eloquent models to lightweight payload items
            $items = [];
            foreach ($p->items() as $row) {
                $items[] = [
                    'id'            => (int) $row->id,
                    'uuid'          => $row->uuid,
                    'name'          => $row->name,
                    'location'      => [
                        'lat' => $row->location_lat !== null ? (float) $row->location_lat : null,
                        'lon' => $row->location_lon !== null ? (float) $row->location_lon : null,
                    ],
                    'sensitivity'   => $row->sensitivity,
                    'overall_score' => (int) $row->overall_score,
                    'diseases'      => $row->diseases ?? [],
                    'alerts'        => $row->alerts ?? ['pollution' => false, 'sound' => true, 'hours2h' => []],
                    'app_version'   => $row->app_version ?? null,
                    'platform'      => $row->platform ?? null,
                    'fcm_token'     => $row->fcm_token ?? null,
                    'received_at'   => optional($row->received_at)->toIso8601String(),
                    'created_at'    => optional($row->created_at)->toIso8601String(),
                    'updated_at'    => optional($row->updated_at)->toIso8601String(),
                ];
            }

            // Standardized list response with meta
            return Response::json([
                'succeed' => true,
                'status'  => 200,
                'data'    => $items,
                'meta'    => [
                    'page'       => $p->currentPage(),
                    'per_page'   => $p->perPage(),
                    'total'      => $p->total(),
                    'last_page'  => $p->lastPage(),
                    'sort'       => $dir === 'desc' ? "-{$col}" : $col,
                    'filters'    => [
                        'uuid'         => $request->query('uuid'),
                        'search'       => $request->query('search'),
                        'has_location' => $request->boolean('has_location', false),
                    ],
                ],
            ], 200);
        } catch (\Throwable $e) {
            Log::error('HealthAdvisor index failed', ['err' => $e->getMessage()]);
            return Response::json([
                'succeed' => false,
                'status'  => 500,
                'message' => 'Failed to fetch records.',
            ], 500);
        }
    }

    // ---------------------------------------------------------------------
    // DELETE /api/v1/frontend/health-advisor/destroy/{id}
    // Hard-delete a single submission by numeric id
    // ---------------------------------------------------------------------
    public function destroy($id, Request $request)
    {
        try {
            $id = (int) $id;
            if ($id <= 0) {
                return Response::json([
                    'succeed' => false,
                    'status'  => 422,
                    'message' => 'Invalid id.',
                ], 422);
            }

            $row = ClimateHealthAdvisor::query()->find($id);
            if (!$row) {
                return Response::json([
                    'succeed' => false,
                    'status'  => 404,
                    'message' => 'Record not found.',
                ], 404);
            }

            $row->delete();

            return Response::json([
                'succeed' => true,
                'status'  => 200,
                'message' => 'Deleted successfully.',
                'data'    => ['id' => $id],
            ], 200);
        } catch (\Throwable $e) {
            Log::error('HealthAdvisor destroy failed', ['err' => $e->getMessage()]);
            return Response::json([
                'succeed' => false,
                'status'  => 500,
                'message' => 'Failed to delete record.',
            ], 500);
        }
    }

    // ---------------------------------------------------------------------
    // POST /api/v1/frontend/health-advisor/store
    // Upsert by {uuid} + optional (lat,lon). Accepts optional device fields.
    // ---------------------------------------------------------------------
    public function store(Request $request)
    {
        $input = $request->all();

        // 1) Identifier is required (prefer headers; fall back to body)
        $incomingId =
            ($request->header('X-Request-Id') ? (string) $request->header('X-Request-Id') : null)
            ?: ($request->header('X-Client-Id') ? (string) $request->header('X-Client-Id') : null)
            ?: ($input['uuid'] ?? $input['client_id'] ?? null);

        if (!$incomingId || trim($incomingId) === '') {
            return Response::json([
                'succeed' => false,
                'status'  => 422,
                'reason'  => 'invalid',
                'message' => 'Missing identifier.',
            ], 422);
        }
        $uuid = trim($incomingId);

        // 2) Name is required
        $name = trim((string)($input['name'] ?? ''));
        if ($name === '') {
            return Response::json([
                'succeed' => false,
                'status'  => 422,
                'reason'  => 'invalid',
                'message' => 'Validation error',
                'errors'  => ['name' => ['Name is required.']],
            ], 422);
        }

        // 3) Normalize location (rounded to 4 decimals)
        $lat = isset($input['location']['lat']) ? round((float)$input['location']['lat'], 4) : null;
        $lon = isset($input['location']['lon']) ? round((float)$input['location']['lon'], 4) : null;

        // 4) Other fields with guards/defaults
        $sensitivity = in_array(strtolower((string)($input['sensitivity'] ?? 'normal')), ['sensitive', 'normal', 'relaxed'])
            ? strtolower($input['sensitivity'])
            : 'normal';

        $overallScore = max(0, min(100, (int)($input['overall_score'] ?? 0)));

        $diseases = [];
        if (!empty($input['diseases']) && is_array($input['diseases'])) {
            foreach ($input['diseases'] as $d) {
                $d = strtolower(trim((string)$d));
                if ($d !== '') $diseases[] = $d;
            }
            $diseases = array_values(array_unique($diseases));
        }

        $pollution = (bool)($input['alerts']['pollution'] ?? false);
        $sound     = (bool)($input['alerts']['sound'] ?? true);
        $hours2h   = [];
        if (!empty($input['alerts']['hours2h']) && is_array($input['alerts']['hours2h'])) {
            $hours2h = array_slice(array_unique(array_map('intval', $input['alerts']['hours2h'])), 0, 5);
        }

        // 5) Optional device metadata
        $fcmToken   = isset($input['fcm_token']) ? substr(trim((string)$input['fcm_token']), 0, 2048) : null;
        $platform   = isset($input['platform']) ? substr(strtolower(trim((string)$input['platform'])), 0, 50) : null;
        $appVersion = isset($input['app_version']) ? substr(trim((string)$input['app_version']), 0, 100) : null;

        try {
            // Upsert key: uuid + (optional) exact lat/lon pair
            $query = ClimateHealthAdvisor::where('uuid', $uuid);
            if (!is_null($lat) && !is_null($lon)) {
                $query->where('location_lat', $lat)->where('location_lon', $lon);
            }

            $row = $query->first();

            $data = [
                'uuid'          => $uuid,
                'name'          => $name,
                'location_lat'  => $lat,
                'location_lon'  => $lon,
                'sensitivity'   => $sensitivity,
                'overall_score' => $overallScore,
                'diseases'      => $diseases,
                'alerts'        => [
                    'pollution' => $pollution,
                    'sound'     => $sound,
                    'hours2h'   => $hours2h,
                ],
                'received_at'   => now(),
                'ip'            => $request->ip(),
                'user_agent'    => $request->userAgent(),
            ];

            // Attach optional fields only if present
            if (!empty($fcmToken)) {
                $data['fcm_token']   = $fcmToken;
            }
            if (!empty($platform)) {
                $data['platform']    = $platform;
            }
            if (!empty($appVersion)) {
                $data['app_version'] = $appVersion;
            }

            if ($row) {
                $row->fill($data)->save();
            } else {
                $row = ClimateHealthAdvisor::create($data);
            }
        } catch (\Throwable $e) {
            Log::error('HealthAdvisor store failed', ['err' => $e->getMessage()]);
            return Response::json([
                'succeed' => false,
                'status'  => 500,
                'message' => 'Failed to persist submission.',
            ], 500);
        }

        // Created/updated entity payload
        return Response::json([
            'succeed' => true,
            'status'  => 201,
            'message' => 'Stored successfully',
            'data'    => [
                'id'            => (int)$row->id,
                'uuid'          => $row->uuid,
                'name'          => $row->name,
                'location'      => ['lat' => $row->location_lat, 'lon' => $row->location_lon],
                'sensitivity'   => $row->sensitivity,
                'diseases'      => $row->diseases ?? [],
                'overall_score' => (int)$row->overall_score,
                'alerts'        => $row->alerts ?? [],
                'app_version'   => $row->app_version ?? null,
                'platform'      => $row->platform ?? null,
                'fcm_token'     => $row->fcm_token ?? null,
                'received_at'   => optional($row->received_at)->toIso8601String(),
                'created_at'    => optional($row->created_at)->toIso8601String(),
                'updated_at'    => optional($row->updated_at)->toIso8601String(),
            ],
        ], 201);
    }

    /**
     * notifications
     *
     * Send a debug test push via FCM HTTP v1 (Google) to a single token or topic.
     * The notification content is derived from an internal call to point-assess
     * (no external HTTP) using the provided (lat, lon, z, t) inputs.
     *
     * Request (query/body):
     * - token (string, optional): direct FCM token. If absent, uses `topic` or a fallback test token.
     * - topic (string, optional): FCM topic name (used if token not provided).
     * - lat (float, optional): latitude; default 40.7831 (Manhattan).
     * - lon (float, optional): longitude; default -73.9712.
     * - z (int, optional): zoom hint; default 10.
     * - t (string, optional): time offset param for AQ logic; default '0'.
     *
     * Response (JSON): includes the computed AQ summary, chosen top contributor,
     * HTTP status from FCM, and the raw FCM response for debugging.
     */
    public function notifications(Request $request = null)
    {
        // -------- 0) Safe request creation; set defaults (no external HTTP) ------
        $req = $request ?? request();
        if (!$req instanceof Request) {
            $req = new Request(); // empty request if something unexpected was passed
        }

        // Default AOI: Manhattan, t=0, z=10
        $lat = (float) ($req->input('lat', 40.7831));
        $lon = (float) ($req->input('lon', -73.9712));
        $t   = (string) $req->input('t', '0');
        $z   = (int)    $req->input('z', 10);

        $targetToken = trim((string)($req->input('token', '')));
        $topic       = trim((string)($req->input('topic', '')));

        // Local testing fallback token (DO NOT ship to production)
        $fallbackTestToken = 'fZbH8rOZTEeLrc5Wahuzgh:APA91bHwrli9wVy-z-y9QzwOYw4sZJwsG-XTYa2nnGOxjDxeq3ZWMmSCtenX69orGZ1LGs94bVu8VoCwTRWMQmA9lghWLottJ-VHnbsifnuWkYgV9UBWdJg';

        // Build a fake internal request to reuse the AQ computation code path
        $pointParams = [
            'lat'      => $lat,
            'lon'      => $lon,
            'products' => 'no2,hcho,o3tot',
            'z'        => $z,
            't'        => $t,
            'debug'    => 0,
        ];
        $internalReq = Request::create('/_internal/air-quality/point-assess', 'GET', $pointParams);

        // -------- 1) Call neighbor controller directly (no HTTP round-trip) -----
        try {
            /** @var AirQualitiesController $aq */
            $aq = app(AirQualitiesController::class);
            $resp = $aq->pointAssess($internalReq);

            if ($resp instanceof JsonResponse) {
                $respBody = $resp->getData(true);
            } elseif (is_array($resp)) {
                $respBody = $resp;
            } else {
                $respBody = json_decode(json_encode($resp), true);
            }
        } catch (\Throwable $e) {
            return response()->json([
                'succeed' => false,
                'status'  => 500,
                'message' => 'Internal point-assess call failed.',
                'error'   => $e->getMessage(),
            ], 500);
        }

        if (!is_array($respBody) || empty($respBody['succeed'])) {
            return response()->json([
                'succeed' => false,
                'status'  => 500,
                'message' => 'Invalid point-assess response.',
                'raw'     => $respBody,
            ], 500);
        }

        // -------- 2) Craft summary + notification text ---------------------------
        $overall  = $respBody['overall'] ?? [];
        $score10  = isset($overall['score_10'])  ? (float)$overall['score_10']  : null;
        $score100 = isset($overall['score_100']) ? (int)$overall['score_100']   : null;
        $level    = $overall['recommended_actions']['level']  ?? 'Unknown';
        $advice   = $overall['recommended_actions']['advice'] ?? null;

        $productsMap = $respBody['products'] ?? [];
        $topName = null; $topScore = -1;
        foreach (['no2','hcho','o3tot'] as $p) {
            $s = $productsMap[$p]['score']['score_10'] ?? null;
            if ($s !== null && (float)$s > $topScore) {
                $topScore = (float)$s;
                $topName  = $p;
            }
        }
        if ($topName === null) { $topName = 'no2'; }
        $labels   = ['no2' => 'NO₂', 'hcho' => 'HCHO', 'o3tot' => 'O₃'];
        $topLabel = $labels[$topName] ?? strtoupper($topName);

        $title = 'Air quality • Manhattan';
        $body  = ($level ?? 'Status')
               . ($score100 !== null ? " ({$score100}/100)" : '')
               . " • {$topLabel} is main contributor";

        if ($advice) {
            // Keep body compact; avoid overly long lines in notifications
            $shortAdvice = mb_strimwidth($advice, 0, 90, '…', 'UTF-8');
            $body .= " • " . $shortAdvice;
        }

        // -------- 3) Send via FCM HTTP v1 (Google) ------------------------------
        // Service account JSON must be placed next to this controller file
        $keyFile = __DIR__ . '/climatewise-8f4c6-firebase-adminsdk-fbsvc-eb9cb3bbca.json';
        if (!File::exists($keyFile)) {
            return response()->json([
                'succeed' => false,
                'status'  => 500,
                'message' => "Service account JSON not found at {$keyFile}",
            ], 500);
        }
        $svc = json_decode(File::get($keyFile), true);
        if (!is_array($svc) || empty($svc['project_id']) || empty($svc['client_email']) || empty($svc['private_key'])) {
            return response()->json([
                'succeed' => false,
                'status'  => 500,
                'message' => 'Invalid service account JSON.',
            ], 500);
        }

        // Obtain OAuth2 access token for Firebase Cloud Messaging scope
        try {
            $creds = new ServiceAccountCredentials(
                ['https://www.googleapis.com/auth/firebase.messaging'], $svc
            );
            $tok = $creds->fetchAuthToken();
            if (empty($tok['access_token'])) {
                throw new \RuntimeException('Failed to fetch access token.');
            }
            $accessToken = $tok['access_token'];
        } catch (\Throwable $e) {
            return response()->json([
                'succeed' => false,
                'status'  => 500,
                'message' => 'Failed to obtain Google access token.',
                'error'   => $e->getMessage(),
            ], 500);
        }

        // Choose target: token > topic > local fallback
        $target = [];
        if ($targetToken !== '') {
            $target['token'] = $targetToken;
        } elseif ($topic !== '') {
            $target['topic'] = $topic;
        } else {
            $target['token'] = $fallbackTestToken; // testing only
        }

        // Build FCM message payload (notification + data)
        $fcmMessage = [
            'message' => $target + [
                'notification' => ['title' => $title, 'body' => $body],
                'data' => [
                    'route'   => '/health',
                    'city'    => 'Manhattan,NY',
                    'score10' => (string)($score10 ?? ''),
                    'score100'=> (string)($score100 ?? ''),
                    'level'   => (string)$level,
                    'top'     => (string)$topName,
                    'sent_at' => now()->toIso8601String(),
                ],
                'android' => [
                    'priority' => 'HIGH',
                    'notification' => ['channel_id' => 'high_importance_channel'],
                ],
            ],
        ];

        $fcmUrl = "https://fcm.googleapis.com/v1/projects/{$svc['project_id']}/messages:send";

        try {
            $guzzle = new GuzzleClient(['timeout' => 12, 'connect_timeout' => 5]);
            $res = $guzzle->post($fcmUrl, [
                'headers' => [
                    'Authorization' => "Bearer {$accessToken}",
                    'Content-Type'  => 'application/json',
                ],
                'json' => $fcmMessage,
            ]);
            $fcmStatus = $res->getStatusCode();
            $fcmResp   = json_decode((string)$res->getBody(), true);
        } catch (\GuzzleHttp\Exception\ClientException $ge) {
            $r = $ge->getResponse();
            return response()->json([
                'succeed' => false,
                'status'  => $r ? $r->getStatusCode() : 500,
                'message' => 'FCM client error',
                'error'   => $r ? json_decode((string)$r->getBody(), true) : $ge->getMessage(),
            ], $r ? $r->getStatusCode() : 500);
        } catch (\Throwable $e) {
            return response()->json([
                'succeed' => false,
                'status'  => 500,
                'message' => 'Failed to send FCM notification',
                'error'   => $e->getMessage(),
            ], 500);
        }

        // -------- 4) Debug-friendly final JSON -----------------------------------
        return response()->json([
            'succeed' => true,
            'status'  => 200,
            'message' => 'Notification sent',
            'point'   => ['lat'=>$lat,'lon'=>$lon,'name'=>'Manhattan, NY'],
            'overall' => [
                'score_10'  => $score10,
                'score_100' => $score100,
                'level'     => $level,
                'advice'    => $advice,
            ],
            'top_contributor' => [
                'product' => $topName,
                'label'   => $topLabel,
                'score10' => $topScore,
            ],
            'fcm' => [
                'http_status' => $fcmStatus ?? null,
                'response'    => $fcmResp   ?? null,
            ],
        ], 200);
    }
}
