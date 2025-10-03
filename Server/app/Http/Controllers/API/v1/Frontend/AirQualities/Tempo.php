<?php

namespace App\Http\Controllers\API\V1\Frontend\AirQualities;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;

/**
 * TEMPO/Harmony service (V04): heavy logic in getTempoData
 * Output is always an array with a 'status' key (controller will JSON-encode).
 */
class Tempo
{
    /** Stable Harmony base URL */
    private const HARMONY_BASE = 'https://harmony.earthdata.nasa.gov';

    /**
     * Products registry for V04 only
     * concept_id/entry_id are updated for V04.
     */
    private const PRODUCTS = [
        'no2' => [
            'concept_id' => 'C3685896708-LARC_CLOUD', // V04
            'entry_id'   => 'TEMPO_NO2_L3_V04',
            'vars_all'   => [
                'product/vertical_column_troposphere',
                'product/vertical_column_troposphere_uncertainty',
                'product/main_data_quality_flag',
                'support_data/amf_cloud_fraction',
            ],
            'var_main'   => 'product/vertical_column_troposphere',
        ],
        'hcho' => [
            'concept_id' => 'C3685897141-LARC_CLOUD', // V04
            'entry_id'   => 'TEMPO_HCHO_L3_V04',
            'vars_all'   => [
                'product/vertical_column',
                'product/vertical_column_uncertainty',
                'product/main_data_quality_flag',
                'support_data/amf_cloud_fraction',
            ],
            'var_main'   => 'product/vertical_column',
        ],
        'o3tot' => [
            'concept_id' => 'C3685896625-LARC_CLOUD', // V04
            'entry_id'   => 'TEMPO_O3TOT_L3_V04',
            'vars_all'   => [
                'product/column_amount_o3',
                'product/radiative_cloud_frac',
                'support_data/cloud_pressure',
            ],
            'var_main'   => 'product/column_amount_o3',
        ],
        'cldo4' => [
            'concept_id' => 'C3685896149-LARC_CLOUD', // V04
            'entry_id'   => 'TEMPO_CLDO4_L3_V04',
            'vars_all'   => ['product/cloud_fraction','product/cloud_pressure'],
            'var_main'   => 'product/cloud_fraction',
        ],
    ];

    /** Defaults, NA bounds, SSRF allowlist, etc. */
    private const HOURS_WINDOW_DEFAULT     = 72;
    private const HTTP_TIMEOUT_SEC_DEFAULT = 1200;
    private const UA                       = 'ShahrShab-TEMPO-MVP/1.1';
    private const CLIENT_ID                = 'tempo-mvp-app';

    private const NA_LAT1 = 15.0;
    private const NA_LAT2 = 75.0;
    private const NA_LON1 = -170.0;
    private const NA_LON2 = -50.0;

    private const MIN_FREE_BYTES_DEFAULT = 5368709120; // 5GB
    private const ALLOWED_RESULT_HOSTS = [
        'harmony.earthdata.nasa.gov','harmony.earthdata.nasa.gov:443','harmony.earthdata.nasa.gov:80',
        'cmr.earthdata.nasa.gov','cmr.earthdata.nasa.gov:443',
        's3.amazonaws.com','s3-us-west-2.amazonaws.com','s3.us-west-2.amazonaws.com',
    ];

    /* ----------------------------- Public API ----------------------------- */

    /**
     * Note: Per your code, the incoming method name is "build" (not handle).
     */
    public function build(Request $request)
    {
        $action = $request->query('action', 'capabilities');
        $nc     = $this->normalizeNc($request->query('nc', 'no2'));

        // Resolve collection (V04 only)
        $collectionId = $this->resolveConceptId($nc);
        if (!$collectionId && !in_array($action, ['ping'])) {
            return ['succeed'=>false,'status'=>400,'message'=>"Collection ID for '{$nc}' not found (CMR). Please set entry_id/collection_id in config or try again later.",'nc'=>$nc];
        }

        // ping (no token required)
        if ($action === 'ping') {
            try {
                $url  = rtrim(self::HARMONY_BASE, '/') . '/capabilities'
                      . ($collectionId ? ('?collectionId=' . urlencode($collectionId)) : '');
                $resp = Http::withHeaders($this->edlHeaders('application/json'))->timeout(20)->get($url);
                return [
                    'succeed'=>$resp->ok(),
                    'status'=>$resp->status(),
                    'message'=>$resp->ok() ? 'Connection and auth are OK.' : 'Problem with connection/auth.',
                    'nc'=>$nc,
                ];
            } catch (\Throwable $e) {
                return ['succeed'=>false,'status'=>500,'message'=>'Ping failed (network/SSL/DNS).','error'=>$e->getMessage(),'nc'=>$nc];
            }
        }

        // From here on, token is required
        if (!$this->edlToken() && in_array($action, ['capabilities','rangeset_sample','job_status','job_download','harvest_window','ingest_window'])) {
            return ['succeed'=>false,'status'=>401,'message'=>'EDL token is not set. Please define TEMPO_EDL_TOKEN in ENV.','nc'=>$nc];
        }

        // 1) capabilities
        if ($action === 'capabilities') {
            $url = rtrim(self::HARMONY_BASE, '/') . '/capabilities?collectionId=' . urlencode($collectionId);
            try {
                $resp = Http::withHeaders($this->edlHeaders('application/json'))->timeout(60)->retry(2,500)->get($url);
                if (!$resp->ok()) {
                    return ['succeed'=>false,'status'=>$resp->status(),'message'=>'Harmony service error while reading capabilities.','body'=>$resp->body(),'nc'=>$nc];
                }
                $json = $resp->json();
                return [
                    'succeed'=>true,'status'=>200,'message'=>'Harmony capabilities fetched.','nc'=>$nc,
                    'data'=>[
                        'conceptId'=>$json['conceptId']??null,
                        'shortName'=>$json['shortName']??null,
                        'variableSubset'=>$json['variableSubset']??null,
                        'bboxSubset'=>$json['bboxSubset']??null,
                        'outputFormats'=>$json['outputFormats']??[],
                        'variables_preview'=>collect($json['variables']??[])->take(8)->values()->all(),
                        'variables_count'=>isset($json['variables'])?count($json['variables']):0,
                    ],
                ];
            } catch (\Throwable $e) {
                Log::error('Harmony capabilities error: '.$e->getMessage());
                return ['succeed'=>false,'status'=>500,'message'=>'Harmony not reachable (timeout/network).','error'=>$e->getMessage(),'nc'=>$nc];
            }
        }

        // 2) rangeset_sample → submit job
        if ($action === 'rangeset_sample') {
            $lat1 = (float)$request->query('lat1', self::NA_LAT1);
            $lat2 = (float)$request->query('lat2', self::NA_LAT2);
            $lon1 = (float)$request->query('lon1', self::NA_LON1);
            $lon2 = (float)$request->query('lon2', self::NA_LON2);
            [$south,$north,$west,$east] = $this->normalizeBounds($lat1,$lat2,$lon1,$lon2);

            $vars = $this->variablesFor($nc);
            $granuleId = trim((string)$request->query('granuleId',''));

            $t0 = null; $t1 = null;
            if ($granuleId === '') {
                $lst = $this->cmrListGranules($collectionId,$south,$north,$west,$east,1,5,1);
                if (empty($lst)) {
                    return ['succeed'=>false,'status'=>404,'message'=>'No granule found in the last 1 hour.','nc'=>$nc];
                }
                $granuleId = $lst[0]['id'];
                $t0 = $lst[0]['t0'] ?? null;
                $t1 = $lst[0]['t1'] ?? null;
            }

            $attempts = [];
            $res = $this->harmonySubmitJob(
                $collectionId, $granuleId, $south,$north,$west,$east,
                $vars['all'], $vars['main'], $t0, $t1, $attempts
            );
            if (!$res['ok']) {
                return ['succeed'=>false,'status'=>400,'message'=>'Coverages did not return NetCDF.','attempts'=>$attempts,'nc'=>$nc];
            }
            return [
                'succeed'=>true,'status'=>202,'message'=>'Job is processing (Harmony).',
                'job_url'=>$res['job_url'],
                'vars_ok'=>$attempts ? explode(',', $attempts[count($attempts)-1]['vars']) : [],
                'nc'=>$nc,
            ];
        }

        // 3) job_status
        if ($action === 'job_status') {
            $url = $request->query('url');
            $id  = $request->query('id');
            if (!$url && $id) $url = rtrim(self::HARMONY_BASE,'/').'/jobs/'.trim($id);
            if (!$url) return ['succeed'=>false,'status'=>400,'message'=>'Parameter url or id is required.','nc'=>$nc];

            try {
                $resp = Http::withHeaders($this->edlHeaders('application/json'))->timeout(60)->get($url);
                $json = $resp->json();
                $results = $this->extractJobDataLinks($json);
                return [
                    'succeed'=>$resp->ok(),
                    'status'=>$resp->status(),
                    'message'=>$resp->ok() ? 'Job status fetched.' : 'Failed to fetch job status.',
                    'nc'=>$nc,
                    'data'=>[
                        'job'=>[
                            'status'=>$json['status']??null,
                            'progress'=>$json['progress']??null,
                            'message'=>$json['message']??null,
                            'created'=>$json['createdAt']??null,
                            'updated'=>$json['updatedAt']??null,
                            'jobID'=>$json['jobID']??null,
                        ],
                        'result_urls'=>$results,
                        'links_preview'=>array_slice($json['links'] ?? [], 0, 6),
                    ],
                ];
            } catch (\Throwable $e) {
                return ['succeed'=>false,'status'=>500,'message'=>'Exception while reading job status.','error'=>$e->getMessage(),'nc'=>$nc];
            }
        }

        // 4) job_download
        if ($action === 'job_download') {
            $resultUrl = $request->query('result_url');
            if (!$resultUrl) return ['succeed'=>false,'status'=>400,'message'=>'Parameter result_url is required.','nc'=>$nc];

            if (!$this->isAllowedResultUrl($resultUrl)) {
                return ['succeed'=>false,'status'=>403,'message'=>'result_url domain is not allowed.','nc'=>$nc];
            }

            $dir = $this->destDir($nc);
            if (!is_dir($dir)) @mkdir($dir, 0775, true);

            $free = 0;
            if (!$this->hasEnoughDisk($dir, $free)) {
                return [
                    'succeed'=>false,'status'=>507,'message'=>'Not enough disk space to download job output.',
                    'free_bytes'=>$free,'min_required'=>$this->minFreeBytes(),'nc'=>$nc,
                ];
            }

            $dest = $dir . '/' . $nc . '_job_' . date('Ymd_His') . '.nc';
            $dl = $this->downloadNcDirect($resultUrl, $dest);
            if (!$dl['ok']) {
                return ['succeed'=>false,'status'=>$dl['status'] ?? 502,'message'=>'NetCDF download failed.','body'=>$dl['body'] ?? null,'nc'=>$nc];
            }
            $rel = str_replace(storage_path('app').'/','', $dest);
            return ['succeed'=>true,'status'=>200,'message'=>'Job output saved.','file'=>$rel,'size_bytes'=>$dl['bytes'],'nc'=>$nc];
        }

        // 5) harvest_window / ingest_window
        if ($action === 'harvest_window' || $action === 'ingest_window') {
            $lockKey = "tempo:harvest:{$nc}";
            $lock = Cache::lock($lockKey, self::HTTP_TIMEOUT_SEC_DEFAULT + 60);
            if (!$lock->get()) {
                return ['succeed'=>false,'status'=>429,'message'=>"harvest_window for '{$nc}' is already running. Try again later.",'nc'=>$nc];
            }

            try {
                $hours = (int) $request->query('hours', self::HOURS_WINDOW_DEFAULT);
                if ($hours < 1) $hours = self::HOURS_WINDOW_DEFAULT;

                $limit = (int) $request->query('limit', 10);
                if ($limit < 1)  $limit = 1;
                if ($limit > 50) $limit = 50;

                $lat1 = (float) $request->query('lat1', self::NA_LAT1);
                $lat2 = (float) $request->query('lat2', self::NA_LAT2);
                $lon1 = (float) $request->query('lon1', self::NA_LON1);
                $lon2 = (float) $request->query('lon2', self::NA_LON2);
                [$south, $north, $west, $east] = $this->normalizeBounds($lat1, $lat2, $lon1, $lon2);
                $bbox = [$south, $north, $west, $east];

                $dir = $this->destDir($nc);
                if (!is_dir($dir)) @mkdir($dir, 0775, true);

                $freePre = 0;
                if (!$this->hasEnoughDisk($dir, $freePre)) {
                    return ['succeed'=>false,'status'=>507,'message'=>'Not enough disk space (pre-check).','free_bytes'=>$freePre,'min_required'=>$this->minFreeBytes(),'nc'=>$nc];
                }

                $vars = $this->variablesFor($nc);

                $granules   = $this->cmrListGranules($collectionId, $south,$north,$west,$east, $hours, 200, 10);
                $granuleIds = array_values(array_unique(array_map(fn($g) => $g['id'], $granules)));

                $metaById = [];
                foreach ($granules as $g) $metaById[$g['id']] = $g;

                $downloaded = [];
                $skipped = [];
                $failed = [];
                $downloadedNew = 0;

                foreach ($granuleIds as $gid) {
                    if ($downloadedNew >= $limit) break;

                    $dest = $dir . '/' . $nc . '_' . $gid . '.nc';
                    if (file_exists($dest) && filesize($dest) > 2048) {
                        $skipped[] = $gid;
                        continue;
                    }

                    $t0 = $metaById[$gid]['t0'] ?? null;
                    $t1 = $metaById[$gid]['t1'] ?? null;

                    $attempts = [];
                    $submit = $this->harmonySubmitJob(
                        $collectionId, $gid, $south,$north,$west,$east,
                        $vars['all'], $vars['main'], $t0, $t1, $attempts
                    );
                    if (!$submit['ok'] || !$submit['job_url']) {
                        $failed[] = ['gid'=>$gid,'why'=>'submit_failed','attempts'=>$attempts];
                        continue;
                    }

                    $poll = $this->harmonyPoll($submit['job_url'], 900, 3);
                    if (!$poll['ok'] || empty($poll['result_urls'])) {
                        $failed[] = ['gid'=>$gid,'why'=>'poll_failed','status'=>$poll['status'] ?? null];
                        continue;
                    }

                    $freeMid = 0;
                    if (!$this->hasEnoughDisk($dir, $freeMid)) {
                        $failed[] = ['gid'=>$gid,'why'=>'no_disk_space_pre_download','free_bytes'=>$freeMid];
                        break;
                    }

                    $ncUrl = $poll['result_urls'][0];
                    if (!$this->isAllowedResultUrl($ncUrl)) {
                        $failed[] = ['gid'=>$gid,'why'=>'disallowed_url','url'=>$ncUrl];
                        continue;
                    }

                    $dl = $this->downloadNcDirect($ncUrl, $dest);
                    if (!$dl['ok']) {
                        $failed[] = ['gid'=>$gid,'why'=>'download_failed','status'=>$dl['status'] ?? null];
                        if (file_exists($dest)) @unlink($dest);
                    } else {
                        $downloaded[] = [
                            'gid'=>$gid,'bytes'=>$dl['bytes'],
                            'vars_used'=>$submit['vars_used'] ?? null,
                            'multi'=>$submit['multi'] ?? null,
                        ];
                        $downloadedNew++;
                    }
                }

                $cleanup = $this->cleanupOutsideWindow($nc, $granuleIds);
                $this->updateIndex($nc, $metaById, $downloaded, $cleanup['deleted'], $bbox);

                $freePost = 0; $this->hasEnoughDisk($dir, $freePost);

                return [
                    'succeed'=>true,'status'=>200,'message'=>'harvest_window executed.','nc'=>$nc,
                    'data'=>[
                        'window_hours'=>$hours,
                        'found'=>count($granuleIds),
                        'downloaded_new'=>$downloadedNew,
                        'skipped_exist'=>count($skipped),
                        'failed'=>count($failed),
                        'deleted_old'=>count($cleanup['deleted']),
                        'disk_free_pre'=>$freePre,
                        'disk_free_post'=>$freePost,
                    ],
                    'details'=>[
                        'downloaded'=>$downloaded,
                        'skipped'=>$skipped,
                        'failed'=>$failed,
                        'deleted'=>$cleanup['deleted'],
                    ],
                ];
            } finally {
                optional($lock)->release();
            }
        }

        // default
        return ['succeed'=>false,'status'=>400,'message'=>'Invalid action. Use action=ping | capabilities | rangeset_sample | job_status | job_download | harvest_window.','nc'=>$nc];
    }

    /* ----------------------- Private helpers (no structural change) ---------------------- */

    private function edlToken(): ?string
    {
        $env = (string) config('services.tempo.edl_token', env('TEMPO_EDL_TOKEN', ''));
        $tk  = trim($env);

        // NOTE: The token below comes from your code — kept as-is.
        $tk = 'put_your_API_HERE';
        return $tk !== '' ? $tk : null;
    }

    private function edlHeaders(?string $accept = null): array
    {
        $h = ['User-Agent'=>self::UA,'Client-Id'=>self::CLIENT_ID];
        if ($accept) $h['Accept'] = $accept;
        $tk = $this->edlToken();
        if ($tk) $h['Authorization'] = 'Bearer '.$tk;
        return $h;
    }

    private function normalizeNc(string $nc = null): string
    {
        $nc = strtolower(trim($nc ?? 'no2'));
        return array_key_exists($nc, self::PRODUCTS) ? $nc : 'no2';
    }

    private function resolveConceptId(string $nc): ?string
    {
        $cfg = (string) config("services.tempo.collection_ids.$nc", '');
        if ($cfg !== '') return $cfg;

        $meta = self::PRODUCTS[$nc];
        if (!empty($meta['concept_id'])) return $meta['concept_id'];

        $entryId = $meta['entry_id'] ?? '';
        if ($entryId === '') return null;

        $qs = http_build_query(['entry_id[]'=>$entryId,'provider_short_name[]'=>'LARC_CLOUD'], '', '&', PHP_QUERY_RFC3986);
        $url  = "https://cmr.earthdata.nasa.gov/search/collections.json?$qs";
        $resp = Http::withHeaders(['Accept'=>'application/json','User-Agent'=>self::UA])->timeout(20)->retry(2,500)->get($url);
        if (!$resp->ok()) return null;
        $items = $resp->json('feed.entry') ?? [];
        foreach ($items as $e) {
            $cid = $e['id'] ?? $e['concept_id'] ?? null;
            if ($cid) return $cid;
        }
        return null;
    }

    private function variablesFor(string $nc): array
    {
        $meta = self::PRODUCTS[$nc];
        return ['all'=>$meta['vars_all'],'main'=>$meta['var_main']];
    }

    private function coveragesRoot(string $collectionConceptId): string
    {
        return rtrim(self::HARMONY_BASE,'/').'/'.$collectionConceptId.'/ogc-api-coverages/1.0.0';
    }

    private function edrCubeRoot(string $collectionConceptId): string
    {
        return rtrim(self::HARMONY_BASE,'/').'/ogc-api-edr/1.1.0/collections/'.$collectionConceptId.'/cube';
    }

    private function destDir(string $nc): string { return storage_path("app/tempo/{$nc}"); }
    private function indexPath(string $nc): string { return storage_path("app/tempo/{$nc}/index.json"); }

    private function normalizeBounds(float $lat1, float $lat2, float $lon1, float $lon2): array
    {
        $south=min($lat1,$lat2); $north=max($lat1,$lat2); $west=min($lon1,$lon2); $east=max($lon1,$lon2);
        return [$south,$north,$west,$east];
    }

    private function cmrListGranules(string $collectionConceptId,float $lat1,float $lat2,float $lon1,float $lon2,int $hoursBack,int $pageSize=200,int $maxPages=20): array
    {
        [$south,$north,$west,$east] = $this->normalizeBounds($lat1,$lat2,$lon1,$lon2);
        $end   = gmdate('Y-m-d\TH:i:s\Z');
        $start = gmdate('Y-m-d\TH:i:s\Z', time() - 3600 * max(1, $hoursBack));

        $page=1; $all=[];
        while ($page <= $maxPages) {
            $qs = http_build_query([
                'collection_concept_id'=>$collectionConceptId,
                'temporal'=>$start.','.$end,
                'bounding_box'=>"$west,$south,$east,$north",
                'sort_key[]'=>'-start_date',
                'page_size'=>$pageSize,
                'page_num'=>$page,
            ], '', '&', PHP_QUERY_RFC3986);

            $url  = 'https://cmr.earthdata.nasa.gov/search/granules.json?'.$qs;
            $resp = Http::withHeaders(['Accept'=>'application/json','User-Agent'=>self::UA])->timeout(30)->retry(2,500)->get($url);
            if (!$resp->ok()) break;

            $entries = $resp->json('feed.entry') ?? [];
            if (empty($entries)) break;

            foreach ($entries as $e) {
                $gid = $e['id'] ?? $e['concept_id'] ?? null;
                if ($gid) $all[] = ['id'=>$gid,'t0'=>$e['time_start'] ?? null,'t1'=>$e['time_end'] ?? null,'name'=>$e['title'] ?? null];
            }
            if (count($entries) < $pageSize) break;
            $page++;
        }
        return $all;
    }

    private function harmonySubmitJob(string $collectionConceptId,string $granuleId,float $lat1,float $lat2,float $lon1,float $lon2,array $varsAll,string $varMain,?string $t0,?string $t1,array &$attemptLog): array
    {
        [$south,$north,$west,$east] = $this->normalizeBounds($lat1,$lat2,$lon1,$lon2);
        $base = $this->coveragesRoot($collectionConceptId).'/collections/parameter_vars/coverage/rangeset';

        $timeSubset = null;
        if ($t0 && $t1) {
            $t0s = str_replace('"','',$t0); $t1s = str_replace('"','',$t1);
            $timeSubset = rawurlencode("time(\"{$t0s}\":\"{$t1s}\")");
        }

        $attempt = function (string $varsCsv, bool $isFallback = false) use ($granuleId,$south,$north,$west,$east,$base,$timeSubset,&$attemptLog) {
            $qs = ['variable'=>$varsCsv,'maxResults'=>1,'format'=>'application/x-netcdf4','forceAsync'=>'true','skipPreview'=>'true','granuleId'=>$granuleId];
            $enc = http_build_query($qs, '', '&', PHP_QUERY_RFC3986);
            $enc .= '&subset=' . rawurlencode("lat({$south}:{$north})");
            $enc .= '&subset=' . rawurlencode("lon({$west}:{$east})");
            if ($timeSubset) $enc .= '&subset=' . $timeSubset;
            $url = $base.'?'.$enc;

            $t0   = microtime(true);
            $resp = Http::withHeaders($this->edlHeaders('application/x-netcdf4'))->timeout(60)->connectTimeout(15)->retry(1,700)->get($url);
            $t    = round(microtime(true) - $t0, 3);

            $attemptLog[] = ['vars'=>$varsCsv,'status'=>$resp->status(),'elapsed'=>$t,'url'=>$url,'body'=>$resp->ok()?null:mb_substr($resp->body(),0,500,'UTF-8')];

            if ($isFallback) Log::info('[TEMPO] Coverages fallback to main-var only', ['granule'=>$granuleId,'url'=>$url]);

            if ($resp->status() === 202) {
                $jobUrl = $resp->header('location') ?? $resp->header('content-location') ?? null;
                return ['ok'=>true,'job_url'=>$jobUrl,'multi'=>(strpos($varsCsv,',')!==false),'vars_used'=>$varsCsv];
            }
            $ct = strtolower($resp->header('content-type',''));
            if ($resp->ok() && strpos($ct,'application/json') !== false) {
                $js = $resp->json();
                $jobId = $js['jobID'] ?? null;
                if ($jobId) {
                    return ['ok'=>true,'job_url'=>rtrim(self::HARMONY_BASE,'/').'/jobs/'.$jobId,'multi'=>(strpos($varsCsv,',')!==false),'vars_used'=>$varsCsv];
                }
            }
            return ['ok'=>false,'job_url'=>null];
        };

        $r  = $attempt(implode(',',$varsAll), false);
        if ($r['ok']) return $r;
        $r2 = $attempt($varMain, true);
        return $r2;
    }

    private function harmonyPoll(string $jobUrl, int $maxWaitSec = 600, int $sleepSec = 3): array
    {
        if (!$jobUrl) return ['ok'=>false,'status'=>null,'result_urls'=>[]];
        $jobUrl = preg_replace('~/cancel/?$~', '', $jobUrl);

        $t0 = time(); $last = null;
        while (time() - $t0 < $maxWaitSec) {
            $resp = Http::withHeaders($this->edlHeaders('application/json'))->timeout(30)->get($jobUrl);
            if (!$resp->ok()) { $last = ['status'=>$resp->status(),'json'=>null]; sleep($sleepSec); continue; }
            $json = $resp->json();
            $status = strtolower($json['status'] ?? '');
            if (in_array($status, ['successful','complete','completed'])) {
                $urls = $this->extractJobDataLinks($json);
                return ['ok'=>true,'status'=>$status,'result_urls'=>$urls,'json'=>$json];
            }
            if (in_array($status, ['failed','aborted','error'])) {
                return ['ok'=>false,'status'=>$status,'result_urls'=>[],'json'=>$json];
            }
            $last = ['status'=>$status,'json'=>$json];
            sleep($sleepSec);
        }
        return ['ok'=>false,'status'=>'timeout','result_urls'=>[],'last'=>$last];
    }

    private function extractJobDataLinks(array $json): array
    {
        $out = [];
        foreach (($json['links'] ?? []) as $lnk) {
            $href = $lnk['href'] ?? ''; if (!$href) continue;
            $type = strtolower($lnk['type'] ?? ''); $rel = strtolower($lnk['rel'] ?? '');
            $isNetcdf  = (strpos($type,'netcdf') !== false) || preg_match('/\.nc(\.gz|4)?$/i', $href);
            $isDataRel = (strpos($rel,'data') !== false) || (strpos($rel,'results') !== false) || (strpos($rel,'item') !== false);
            if ($isNetcdf || $isDataRel) $out[] = $href;
        }
        return array_values(array_unique($out));
    }

    private function downloadNcDirect(string $url, string $destFile): array
    {
        $resp = Http::withHeaders($this->edlHeaders('application/x-netcdf4'))
            ->timeout(self::HTTP_TIMEOUT_SEC_DEFAULT)->connectTimeout(20)
            ->retry(2,1000)->withOptions(['sink'=>$destFile])->get($url);

        $ct = strtolower($resp->header('content-type',''));
        $ok = $resp->ok() && (strpos($ct,'netcdf') !== false || (file_exists($destFile) && filesize($destFile) > 2048));
        if ($ok) return ['ok'=>true,'bytes'=>filesize($destFile)];
        if (file_exists($destFile)) @unlink($destFile);
        return ['ok'=>false,'bytes'=>0,'status'=>$resp->status(),'body'=>mb_substr($resp->body(),0,600,'UTF-8')];
    }

    private function cleanupOutsideWindow(string $nc, array $validGranuleIds): array
    {
        $dir = $this->destDir($nc);
        if (!is_dir($dir)) return ['deleted'=>[]];
        $keep = array_flip($validGranuleIds);
        $deleted = [];
        foreach (glob($dir . "/{$nc}_*.nc") as $p) {
            if (preg_match("~{$nc}_(G[0-9A-Z\\-]+-LARC_CLOUD)\\.nc$~i", basename($p), $m)) {
                $gid = $m[1];
                if (!isset($keep[$gid])) { @unlink($p); $deleted[] = basename($p); }
            }
        }
        return ['deleted'=>$deleted];
    }

    private function updateIndex(string $nc, array $metaById, array $downloaded, array $deleted, array $bbox): void
    {
        $path = $this->indexPath($nc);
        $dir  = $this->destDir($nc);

        $idx = [];
        if (file_exists($path)) {
            $raw = @file_get_contents($path);
            if (is_string($raw) && $raw !== '') {
                $parsed = json_decode($raw, true);
                if (is_array($parsed)) $idx = $parsed;
            }
        }

        $upsert = function (string $gid, array $meta, ?int $bytes = null, ?string $varsUsed = null, ?bool $multi = null) use (&$idx, $nc, $bbox) {
            $existing = $idx[$gid] ?? null;
            $savedAt = $existing['saved'] ?? gmdate('Y-m-d\TH:i:s\Z');
            $entry = [
                'file'=>"tempo/{$nc}/{$nc}_{$gid}.nc",
                'bytes'=>$bytes ?? ($existing['bytes'] ?? null),
                't0'=>$meta['t0'] ?? ($existing['t0'] ?? null),
                't1'=>$meta['t1'] ?? ($existing['t1'] ?? null),
                'saved'=>$savedAt,
                'bbox'=>$bbox,
                'subset_time'=>[
                    $meta['t0'] ?? ($existing['subset_time'][0] ?? null),
                    $meta['t1'] ?? ($existing['subset_time'][1] ?? null)
                ],
                'vars_used'=>$varsUsed ?? ($existing['vars_used'] ?? null),
                'multi'=>$multi ?? ($existing['multi'] ?? null),
            ];
            if ($existing && (
                ($existing['t0'] ?? null) !== ($entry['t0'] ?? null) ||
                ($existing['t1'] ?? null) !== ($entry['t1'] ?? null)
            )) {
                $entry['saved'] = gmdate('Y-m-d\TH:i:s\Z');
            }
            $idx[$gid] = $entry;
        };

        foreach ($downloaded as $row) {
            $gid  = $row['gid'];
            $meta = $metaById[$gid] ?? [];
            $upsert($gid, $meta, $row['bytes'] ?? null, $row['vars_used'] ?? null, $row['multi'] ?? null);
        }

        foreach ($metaById as $gid => $meta) {
            $abs = $dir . '/' . $nc . '_' . $gid . '.nc';
            if (is_file($abs) && filesize($abs) > 2048) {
                $bytes = @filesize($abs) ?: null;
                $upsert($gid, $meta, $bytes, null, null);
            }
        }

        if (!empty($deleted)) {
            foreach ($deleted as $fn) {
                if (preg_match("~{$nc}_(G[0-9A-Z\\-]+-LARC_CLOUD)\\.nc$~i", $fn, $m)) unset($idx[$m[1]]);
            }
        }

        $validIds = array_fill_keys(array_keys($metaById), true);
        foreach (array_keys($idx) as $gid) {
            $abs = $dir . '/' . $nc . '_' . $gid . '.nc';
            if (!isset($validIds[$gid]) || !is_file($abs)) unset($idx[$gid]);
        }

        @mkdir(dirname($path), 0775, true);
        @file_put_contents($path, json_encode($idx, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_PRETTY_PRINT));
    }

    private function minFreeBytes(): int
    {
        $cfg = (int) config('services.tempo.min_free_bytes', 0);
        return $cfg > 0 ? $cfg : self::MIN_FREE_BYTES_DEFAULT;
    }

    private function hasEnoughDisk(string $dir, ?int &$freeOut = null): bool
    {
        @mkdir($dir, 0775, true);
        $free = @disk_free_space($dir);
        if ($freeOut !== null) $freeOut = $free ?: 0;
        if ($free === false) return true; // conservative
        return true; // To enforce strict checking, replace with the line below.
        // return $free >= $this->minFreeBytes();
    }

    private function isAllowedResultUrl(string $url): bool
    {
        $parts = @parse_url($url);
        if (!$parts || empty($parts['host'])) return false;
        $host = strtolower($parts['host'] . (isset($parts['port']) ? (':' . $parts['port']) : ''));
        if (in_array($host, self::ALLOWED_RESULT_HOSTS, true)) return true;
        if (preg_match('~(^|\\.)s3[.-][a-z0-9-]+\\.amazonaws\\.com$~i', $host)) return true;
        if (preg_match('~(^|\\.)harmony.*\\.amazonaws\\.com$~i', $host)) return true;
        if (preg_match('~(^|\\.)earthdata\\.nasa\\.gov$~i', $host)) return true;
        return false;
    }
}
