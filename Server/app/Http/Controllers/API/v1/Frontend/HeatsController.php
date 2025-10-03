<?php

namespace App\Http\Controllers\API\V1\Frontend;

use Illuminate\Support\Str;
use App\Http\Controllers\API\V1\Frontend\FrontendBaseController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Log;

/**
 * HeatsController
 *
 * Endpoints for climate heat/anomaly datasets used by the Flutter client:
 * - /countries: per-country snapshot for a given year (tas, anomaly, score)
 * - /country/{ISO3}/{year?}: detailed view for a country + comparisons
 * - /statistics: global top lists, global averages, multi-year trend
 * - /years: available year list extracted from the dataset
 * - /climate-anomalies: server-side builder from CSV sources (ERA5 + CMIP6)
 *
 * Notes:
 * - All inline comments and response messages are in English (per request).
 * - No logic was changed; only comments/strings were translated/refined.
 */
class HeatsController extends FrontendBaseController
{
    public function __construct()
    {
        parent::__construct();
        // Base controller metadata (used by shared frontend scaffolding)
        $this->var['model_type']          = 'post';
        $this->var['model_name']          = 'posts';
        $this->var['model_api']           = 'heats';
        $this->var['model_name_singular'] = Str::singular($this->var['model_name']);
        $this->var['model_class']         = 'App\Models\Post';
        $this->var['model_icon']          = '<i class="iconix icon-book"></i>';
        $this->var['model_view']          = $this->var['model_framework'] . '.frontend.' . $this->var['model_name'];
        $this->var['breadcrumbs'][route('frontend.home')] = __('panel.page_user');
        // $this->var['breadcrumbs'][route('frontend.posts.index')] = __('panel.posts');

        // Whitelists for index/show payloads (if used by base controller)
        $this->var['model_index_fields'] = ['id', 'name', 'description', 'thumbnail'];
        $this->var['model_show_fields']  = ['id', 'name', 'description', 'thumbnail', 'body', 'attributes'];
        $this->var['model_quiz_fields']  = ['id', 'name', 'quizzes'];
    }

    /**
     * Validation rules selector for various controller operations.
     * Currently returns empty or minimal rules; extend as needed.
     */
    public function getRules($params)
    {
        $type                 = $params['type'] ?? 'index';
        $input                = $params['input'] ?? [];
        $model_name           = $params['model_name'] ?? null;
        $model_name_singular  = $params['model_name_singular'] ?? null;
        $$model_name_singular = $params['$model_name_singular'] ?? null;

        $input['language'] = $input['language'] ?? null;

        if ($type == 'index') {
            return [];
        } elseif ($type == 'trash') {
            return [];
        } elseif ($type == 'update') {
            return [];
        } elseif ($type == 'store') {
            return [];
        } elseif ($type == 'show') {
            return [
                'ref'  => 'nullable|in:telegram,instagram,twitter,google',
                'code' => 'nullable|numeric'
            ];
        } else {
            return [];
        }
        return [];
    }

    /**
     * Convert ISO-3 country code to lowercase ISO-2 code.
     */
    function iso3_to_iso2_lower(string $iso3, ?string $fallback = null): ?string
    {
        static $MAP = [
            'AFG' => 'af',
            'ALA' => 'ax',
            'ALB' => 'al',
            'DZA' => 'dz',
            'ASM' => 'as',
            'AND' => 'ad',
            'AGO' => 'ao',
            'AIA' => 'ai',
            'ATA' => 'aq',
            'ATG' => 'ag',
            'ARG' => 'ar',
            'ARM' => 'am',
            'ABW' => 'aw',
            'AUS' => 'au',
            'AUT' => 'at',
            'AZE' => 'az',
            'BHS' => 'bs',
            'BHR' => 'bh',
            'BGD' => 'bd',
            'BRB' => 'bb',
            'BLR' => 'by',
            'BEL' => 'be',
            'BLZ' => 'bz',
            'BEN' => 'bj',
            'BMU' => 'bm',
            'BTN' => 'bt',
            'BOL' => 'bo',
            'BES' => 'bq',
            'BIH' => 'ba',
            'BWA' => 'bw',
            'BVT' => 'bv',
            'BRA' => 'br',
            'IOT' => 'io',
            'BRN' => 'bn',
            'BGR' => 'bg',
            'BFA' => 'bf',
            'BDI' => 'bi',
            'CPV' => 'cv',
            'KHM' => 'kh',
            'CMR' => 'cm',
            'CAN' => 'ca',
            'CYM' => 'ky',
            'CAF' => 'cf',
            'TCD' => 'td',
            'CHL' => 'cl',
            'CHN' => 'cn',
            'CXR' => 'cx',
            'CCK' => 'cc',
            'COL' => 'co',
            'COM' => 'km',
            'COD' => 'cd',
            'COG' => 'cg',
            'COK' => 'ck',
            'CRI' => 'cr',
            'CIV' => 'ci',
            'HRV' => 'hr',
            'CUB' => 'cu',
            'CUW' => 'cw',
            'CYP' => 'cy',
            'CZE' => 'cz',
            'DNK' => 'dk',
            'DJI' => 'dj',
            'DMA' => 'dm',
            'DOM' => 'do',
            'ECU' => 'ec',
            'EGY' => 'eg',
            'SLV' => 'sv',
            'GNQ' => 'gq',
            'ERI' => 'er',
            'EST' => 'ee',
            'SWZ' => 'sz',
            'ETH' => 'et',
            'FLK' => 'fk',
            'FRO' => 'fo',
            'FJI' => 'fj',
            'FIN' => 'fi',
            'FRA' => 'fr',
            'GUF' => 'gf',
            'PYF' => 'pf',
            'ATF' => 'tf',
            'GAB' => 'ga',
            'GMB' => 'gm',
            'GEO' => 'ge',
            'DEU' => 'de',
            'GHA' => 'gh',
            'GIB' => 'gi',
            'GRC' => 'gr',
            'GRL' => 'gl',
            'GRD' => 'gd',
            'GLP' => 'gp',
            'GUM' => 'gu',
            'GTM' => 'gt',
            'GGY' => 'gg',
            'GIN' => 'gn',
            'GNB' => 'gw',
            'GUY' => 'gy',
            'HTI' => 'ht',
            'HMD' => 'hm',
            'VAT' => 'va',
            'HND' => 'hn',
            'HKG' => 'hk',
            'HUN' => 'hu',
            'ISL' => 'is',
            'IND' => 'in',
            'IDN' => 'id',
            'IRN' => 'ir',
            'IRQ' => 'iq',
            'IRL' => 'ie',
            'IMN' => 'im',
            'ISR' => 'il',
            'ITA' => 'it',
            'JAM' => 'jm',
            'JPN' => 'jp',
            'JEY' => 'je',
            'JOR' => 'jo',
            'KAZ' => 'kz',
            'KEN' => 'ke',
            'KIR' => 'ki',
            'PRK' => 'kp',
            'KOR' => 'kr',
            'KWT' => 'kw',
            'KGZ' => 'kg',
            'LAO' => 'la',
            'LVA' => 'lv',
            'LBN' => 'lb',
            'LSO' => 'ls',
            'LBR' => 'lr',
            'LBY' => 'ly',
            'LIE' => 'li',
            'LTU' => 'lt',
            'LUX' => 'lu',
            'MAC' => 'mo',
            'MDG' => 'mg',
            'MWI' => 'mw',
            'MYS' => 'my',
            'MDV' => 'mv',
            'MLI' => 'ml',
            'MLT' => 'mt',
            'MHL' => 'mh',
            'MTQ' => 'mq',
            'MRT' => 'mr',
            'MUS' => 'mu',
            'MYT' => 'yt',
            'MEX' => 'mx',
            'FSM' => 'fm',
            'MDA' => 'md',
            'MCO' => 'mc',
            'MNG' => 'mn',
            'MNE' => 'me',
            'MSR' => 'ms',
            'MAR' => 'ma',
            'MOZ' => 'mz',
            'MMR' => 'mm',
            'NAM' => 'na',
            'NRU' => 'nr',
            'NPL' => 'np',
            'NLD' => 'nl',
            'NCL' => 'nc',
            'NZL' => 'nz',
            'NIC' => 'ni',
            'NER' => 'ne',
            'NGA' => 'ng',
            'NIU' => 'nu',
            'NFK' => 'nf',
            'MKD' => 'mk',
            'MNP' => 'mp',
            'NOR' => 'no',
            'OMN' => 'om',
            'PAK' => 'pk',
            'PLW' => 'pw',
            'PSE' => 'ps',
            'PAN' => 'pa',
            'PNG' => 'pg',
            'PRY' => 'py',
            'PER' => 'pe',
            'PHL' => 'ph',
            'PCN' => 'pn',
            'POL' => 'pl',
            'PRT' => 'pt',
            'PRI' => 'pr',
            'QAT' => 'qa',
            'REU' => 're',
            'ROU' => 'ro',
            'RUS' => 'ru',
            'RWA' => 'rw',
            'BLM' => 'bl',
            'SHN' => 'sh',
            'KNA' => 'kn',
            'LCA' => 'lc',
            'MAF' => 'mf',
            'SPM' => 'pm',
            'VCT' => 'vc',
            'WSM' => 'ws',
            'SMR' => 'sm',
            'STP' => 'st',
            'SAU' => 'sa',
            'SEN' => 'sn',
            'SRB' => 'rs',
            'SYC' => 'sc',
            'SLE' => 'sl',
            'SGP' => 'sg',
            'SXM' => 'sx',
            'SVK' => 'sk',
            'SVN' => 'si',
            'SLB' => 'sb',
            'SOM' => 'so',
            'ZAF' => 'za',
            'SGS' => 'gs',
            'SSD' => 'ss',
            'ESP' => 'es',
            'LKA' => 'lk',
            'SDN' => 'sd',
            'SUR' => 'sr',
            'SJM' => 'sj',
            'SWE' => 'se',
            'CHE' => 'ch',
            'SYR' => 'sy',
            'TWN' => 'tw',
            'TJK' => 'tj',
            'TZA' => 'tz',
            'THA' => 'th',
            'TLS' => 'tl',
            'TGO' => 'tg',
            'TKL' => 'tk',
            'TON' => 'to',
            'TTO' => 'tt',
            'TUN' => 'tn',
            'TUR' => 'tr',
            'TKM' => 'tm',
            'TCA' => 'tc',
            'TUV' => 'tv',
            'UGA' => 'ug',
            'UKR' => 'ua',
            'ARE' => 'ae',
            'GBR' => 'gb',
            'USA' => 'us',
            'UMI' => 'um',
            'URY' => 'uy',
            'UZB' => 'uz',
            'VUT' => 'vu',
            'VEN' => 've',
            'VNM' => 'vn',
            'VGB' => 'vg',
            'VIR' => 'vi',
            'WLF' => 'wf',
            'ESH' => 'eh',
            'YEM' => 'ye',
            'ZMB' => 'zm',
            'ZWE' => 'zw',

            // Territories / special cases
            'XKX' => 'xk', // Kosovo (non-ISO, widely used)
            'ANT' => 'an', // Netherlands Antilles (deprecated)
        ];

        $key = strtoupper(trim($iso3));
        return $MAP[$key] ?? $fallback;
    }

    /**
     * GET /api/v1/frontend/heats/country/{ISO3}/{year?}
     * Detailed slice for a single country at {year}, plus comparison bars.
     */
    public function country(Request $request, $iso_a3, $year = null)
    {
        $iso_a3 = strtoupper($iso_a3);
        $year   = $request->query('year', $year);

        $file = storage_path('app/dl/json/heat.json');
        if (!file_exists($file)) {
            return response()->json([
                'succeed' => false,
                'status'  => 404,
                'message' => 'Data file not found.',
                'year'    => $year,
            ]);
        }

        $json     = file_get_contents($file);
        $heatData = json_decode($json, true);

        if (!isset($heatData['data'][$iso_a3])) {
            return response()->json([
                'succeed' => false,
                'status'  => 404,
                'message' => 'Country not found.',
                'year'    => $year,
            ]);
        }

        // ==== Selected country ====
        $countryData = $heatData['data'][$iso_a3];
        $countryName = $countryData['country'] ?? $iso_a3;

        // Find value for requested year in this country
        $selectedValue = collect($countryData['values'])->first(function ($v) use ($year) {
            return intval($v[0]) == intval($year);
        });

        // If the year is missing for this country
        if (!$selectedValue) {
            return response()->json([
                'succeed' => false,
                'status'  => 404,
                'message' => 'Year not found for this country.',
                'year'    => $year,
            ]);
        }

        $tas     = floatval($selectedValue[1]);
        $anomaly = floatval($selectedValue[2]);

        // Build flag URL using ISO-2 code
        $_iso_a2      = self::iso3_to_iso2_lower($iso_a3);
        $relativePath = "img/flags/1x1/{$_iso_a2}.svg";
        $flag         = url($relativePath);

        // ==== Historical path (from first year up to the requested year) ====
        $history = [];
        foreach ($countryData['values'] as $arr) {
            if (intval($arr[0]) <= intval($year)) {
                $history[] = [
                    'year'    => intval($arr[0]),
                    'tas'     => floatval($arr[1]),
                    'anomaly' => floatval($arr[2]),
                ];
            }
        }

        // ==== Global average and top anomalies for the same year ====
        $allCountries = [];
        foreach ($heatData['data'] as $iso => $row) {
            $item = collect($row['values'])->first(function ($v) use ($year) {
                return intval($v[0]) == intval($year);
            });
            if ($item) {
                $allCountries[] = [
                    'iso_a3'  => $iso,
                    'country' => $row['country'] ?? $iso,
                    'tas'     => floatval($item[1]),
                    'anomaly' => floatval($item[2]),
                ];
            }
        }

        // Global means
        $globalTas     = count($allCountries) ? array_sum(array_column($allCountries, 'tas')) / count($allCountries) : null;
        $globalAnomaly = count($allCountries) ? array_sum(array_column($allCountries, 'anomaly')) / count($allCountries) : null;

        // Top 5 countries by anomaly (excluding the selected country)
        $topCountries = collect($allCountries)
            ->where('iso_a3', '!=', $iso_a3)
            ->sortByDesc('anomaly')
            ->take(5)
            ->values()
            ->all();

        // Bar compare payload (this country + Global + top countries)
        $barCompare = array_merge(
            [
                [
                    'iso_a3'  => $iso_a3,
                    'country' => $countryName,
                    'tas'     => $tas,
                    'anomaly' => $anomaly,
                    'flag'    => $flag
                ],
                [
                    'iso_a3'  => 'GLOBAL',
                    'country' => 'Global Average',
                    'tas'     => $globalTas,
                    'anomaly' => $globalAnomaly,
                    'flag'    => null
                ]
            ],
            array_map(function ($item) {
                $_iso_a2 = self::iso3_to_iso2_lower($item['iso_a3']);
                return [
                    'iso_a3'  => $item['iso_a3'],
                    'country' => $item['country'],
                    'tas'     => $item['tas'],
                    'anomaly' => $item['anomaly'],
                    'flag'    => url("img/flags/1x1/{$_iso_a2}.svg"),
                ];
            }, $topCountries)
        );

        // ==== Response ====
        return response()->json([
            'succeed'      => true,
            'status'       => 200,
            'year'         => $year,
            'country'      => [
                'entity'  => $countryName,
                'iso_a3'  => $iso_a3,
                'tas'     => $tas,
                'anomaly' => $anomaly,
                'flag'    => $flag,
            ],
            'bar_compare'  => $barCompare,
            'history'      => $history,
            'meta'         => [
                'baseline' => $heatData['meta']['baseline'] ?? '',
                'scenario' => $heatData['meta']['scenario'] ?? '',
                'ensemble' => $heatData['meta']['ensemble'] ?? '',
                'units'    => $heatData['meta']['units'] ?? [],
            ]
        ]);
    }

    /**
     * GET /api/v1/frontend/heats/statistics/{year?}
     * Global statistics for a single year: top countries, global average, trend.
     */
    public function statistics(Request $request, $year = null)
    {
        $year = $request->query('year', $year);
        if ($year === null) {
            $year = (int) date('Y');
        }

        $file = storage_path('app/dl/json/heat.json');
        if (!file_exists($file)) {
            return response()->json([
                'succeed'        => false,
                'status'         => 404,
                'message'        => 'Data file not found.',
                'year'           => $year,
                'top_countries'  => [],
                'global_average' => null,
                'trend'          => [],
                'last_real_year' => null
            ]);
        }

        $json     = file_get_contents($file);
        $heatData = json_decode($json, true);

        $countries   = [];
        $allTas      = [];
        $allAnomaly  = [];

        // Collect country slices for the requested year
        foreach ($heatData['data'] as $iso => $country) {
            $item = collect($country['values'])->first(function ($v) use ($year) {
                return intval($v[0]) == intval($year);
            });
            if ($item) {
                $tas     = floatval($item[1]);
                $anomaly = floatval($item[2]);
                $countries[] = [
                    'iso_a3'  => $iso,
                    'name'    => $country['country'],
                    'tas'     => $tas,
                    'anomaly' => $anomaly
                ];
                $allTas[]     = $tas;
                $allAnomaly[] = $anomaly;
            }
        }

        // Top 10 by anomaly (switch to 'tas' if you prefer)
        $top = collect($countries)->sortByDesc('anomaly')->take(10)->values()->toArray();

        // Global averages for the requested year
        $global_average = [
            'tas'     => count($allTas) ? array_sum($allTas) / count($allTas) : null,
            'anomaly' => count($allAnomaly) ? array_sum($allAnomaly) / count($allAnomaly) : null
        ];

        // Global trend: average per year across all countries, from dataset start to target year
        $years      = $heatData['meta']['years'];
        $startYear  = intval($years[0]);
        $endYear    = intval($year);

        $trend          = [];
        $last_real_year = null;

        for ($y = $startYear; $y <= $endYear; $y++) {
            $tasArr     = [];
            $anomalyArr = [];
            foreach ($heatData['data'] as $country) {
                $item = collect($country['values'])->first(function ($v) use ($y) {
                    return intval($v[0]) == intval($y);
                });
                if ($item) {
                    $tasArr[]     = floatval($item[1]);
                    $anomalyArr[] = floatval($item[2]);
                    // Last real year (optional: if a flag exists at index 3)
                    if (!isset($last_real_year) && isset($item[3]) && $item[3] == 'real') {
                        $last_real_year = $y;
                    }
                }
            }
            if (count($tasArr) && count($anomalyArr)) {
                $trend[] = [$y, array_sum($tasArr) / count($tasArr), array_sum($anomalyArr) / count($anomalyArr)];
            }
        }

        // If not detected via flags, default to current year as "last real year"
        if (!$last_real_year) {
            $last_real_year = date('Y');
        }

        return response()->json([
            'succeed'        => true,
            'status'         => 200,
            'message'        => 'Operation successful.',
            'year'           => intval($year),
            'top_countries'  => $top,
            'global_average' => $global_average,
            'trend'          => $trend,
            'last_real_year' => intval($last_real_year)
        ]);
    }

    /**
     * GET /api/v1/frontend/heats/years
     * Returns the list of years available in the dataset.
     */
    public function years()
    {
        $file = storage_path('app/dl/json/heat.json');
        if (!file_exists($file)) {
            return response()->json([
                'succeed' => false,
                'status'  => 404,
                'message' => 'Data file not found.',
                'data'    => []
            ]);
        }

        $json     = file_get_contents($file);
        $heatData = json_decode($json, true);

        $years = [];

        if (!empty($heatData['data'])) {
            // Use the first country to extract the year column set
            $firstCountry = reset($heatData['data']);
            if (isset($firstCountry['values'])) {
                $years = collect($firstCountry['values'])
                    ->map(fn($v) => intval($v[0]))
                    ->values()
                    ->toArray();
            }
        }

        return response()->json([
            'succeed' => true,
            'status'  => 200,
            'message' => 'Operation successful.',
            'data'    => $years
        ]);
    }

    /**
     * GET /api/v1/frontend/heats/countries/{year?}
     * Snapshot for all countries at {year}: tas, anomaly, normalized score (1..10).
     */
    public function countries(Request $request, $year = null)
    {
        $year = $request->query('year', $year);

        if ($year === null) {
            $year = (int) date('Y');
        }

        $file = storage_path('app/dl/json/heat.json');
        if (!file_exists($file)) {
            return response()->json([
                'succeed'       => false,
                'status'        => 404,
                'message'       => 'Data file not found.',
                'current_year'  => $year,
                'data'          => []
            ]);
        }

        $json     = file_get_contents($file);
        $heatData = json_decode($json, true);

        $data = [];
        foreach ($heatData['data'] as $iso => $country) {
            // Find the record for the requested year
            $item = collect($country['values'])->first(function ($v) use ($year) {
                return intval($v[0]) == intval($year);
            });
            if ($item) {
                $tas     = floatval($item[1]);
                $anomaly = floatval($item[2]);
                // Normalize anomaly over a fixed range (e.g., -2..+4) -> score 1..10
                $score   = $this->anomalyScore($anomaly);

                $data[] = [
                    'iso_a3'  => $iso,
                    'tas'     => $tas,
                    'anomaly' => $anomaly,
                    'score'   => $score,
                ];
            }
        }

        return response()->json([
            'succeed'       => true,
            'status'        => 200,
            'message'       => 'Operation successful.',
            'current_year'  => $year,
            'data'          => $data
        ]);
    }

    /**
     * Map a temperature anomaly to a discrete color index (score 1..10).
     * You can tune the min/max buckets as needed.
     */
    private function anomalyScore($anomaly)
    {
        // Assumption: anomalies span from -2 to +4, split into 10 buckets.
        // < -2 => 1, > 4 => 10
        $min   = -2;
        $max   =  4;
        $step  = ($max - $min) / 10;
        $score = intval(floor(($anomaly - $min) / $step)) + 1;
        if ($score < 1)  $score = 1;
        if ($score > 10) $score = 10;
        return $score;
    }

    /**
     * GET /api/v1/frontend/heats/climate-anomalies
     * Server-side composer that fuses historical ERA5 (1950–2023) with CMIP6
     * projections (2024–2100), builds a 1951–1980 baseline (offset −0.4°C to
     * approximate 1850–1900), and emits (tas, anomaly) per country per year.
     *
     * Sources (examples):
     * - https://ds.nccs.nasa.gov/thredds/catalog/AMES/NEX/GDDP-CMIP6/ACCESS-CM2/catalog.html
     * - https://climateknowledgeportal.worldbank.org/download-data
     */
    public function climateAnomalies()
    {
        // Example references (kept as doc-only comments)
        // Area of Focus: All Countries
        // Collection: CMIP6 0.25-degree
        // Type: timeseries
        // Variable: tas - Average Mean Surface Air Temperature
        // Product: Time Series
        // Aggregation: Annual
        // Time Interval: 2015-2100
        // Percentile: Median (50th Percentile) of the Multi-Model Ensemble
        // Scenario: SSP2-4.5
        // Model: Multi-Model Ensemble

        // Historical (ERA5)
        // Area of Focus: All Countries
        // Collection: ERA5 0.25-degree
        // Type: timeseries
        // Variable: tas - Average Mean Surface Air Temperature
        // Product: Time Series
        // Aggregation: Annual
        // Time Interval: 1950-2023
        // Percentile: Mean
        // Scenario: Historical

        // Local file paths
        $futureFile     = storage_path('app/dl/json/cmip6_x0_25_2015_2100.csv');
        $historicalFile = storage_path('app/dl/json/era5_x0_25_1950_2023.csv');

        // Read CSVs to associative arrays
        $historical = $this->readCsvAssoc($historicalFile);
        $future     = $this->readCsvAssoc($futureFile);

        // Extract year columns we care about
        $yearsHist   = $this->extractYearCols(array_keys($historical[0]), 1950, 2023);
        $yearsFuture = $this->extractYearCols(array_keys($future[0]), 2024, 2100);

        // Merge per-country series
        $countries = [];
        foreach ($historical as $row) {
            $code                 = $row['code'];
            $name                 = $row['name'];
            $countries[$code]     = [
                'country' => $name,
                'tas'     => [],
            ];
            // 1950–2023 (historical)
            foreach ($yearsHist as $yearCol => $year) {
                $countries[$code]['tas'][$year] = floatval($row[$yearCol] ?? null);
            }
        }
        // 2024–2100 (future)
        foreach ($future as $row) {
            $code = $row['code'];
            foreach ($yearsFuture as $yearCol => $year) {
                // Skip if already populated
                if (!isset($countries[$code]['tas'][$year]) && isset($row[$yearCol])) {
                    $countries[$code]['tas'][$year] = floatval($row[$yearCol]);
                }
            }
        }

        // Build baseline and compute anomaly for each country/year
        $output = [];
        foreach ($countries as $code => $country) {
            // 1951–1980 baseline; minus 0.4°C shift to approximate 1850–1900
            $baselineYears = range(1951, 1980);
            $baselineVals  = array_filter($country['tas'], function ($v, $k) use ($baselineYears) {
                return in_array($k, $baselineYears);
            }, ARRAY_FILTER_USE_BOTH);
            $baseline = (count($baselineVals) > 0)
                ? (array_sum($baselineVals) / count($baselineVals)) - 0.4
                : null;

            $values = [];
            foreach ($country['tas'] as $year => $tas) {
                if ($tas !== null && $baseline !== null) {
                    $anomaly   = round($tas - $baseline, 2);
                    $values[]  = [intval($year), round($tas, 2), $anomaly];
                }
            }
            if (count($values)) {
                $output[$code] = [
                    'country' => $country['country'],
                    'values'  => $values,
                ];
            }
        }

        // Metadata for the emitted JSON
        $meta = [
            'baseline' => '1951–1980 minus 0.4°C ≈ 1850–1900',
            'scenario' => 'SSP2-4.5',
            'ensemble' => 'median',
            'units'    => [
                'tas'     => '°C (absolute)',
                'anomaly' => '°C relative to baseline'
            ],
            'years' => [1950, 2100]
        ];

        return response()->json([
            'meta' => $meta,
            'data' => $output,
        ]);
    }

    // ----------------------- Helpers: CSV parsing -----------------------

    /**
     * Read a CSV file into an array of associative rows.
     * Assumes the first line is header; strips UTF-8 BOM if present.
     */
    private function readCsvAssoc($filename)
    {
        $data = [];
        if (($handle = fopen($filename, 'r')) !== false) {
            $header = null;
            while (($row = fgetcsv($handle)) !== false) {
                if (!$header) {
                    // Remove BOM from the first key if present
                    $row[0] = preg_replace('/^\x{FEFF}/u', '', $row[0]);
                    $header = $row;
                } else {
                    $data[] = array_combine($header, $row);
                }
            }
            fclose($handle);
        }
        return $data;
    }

    /**
     * From a list of CSV column names, extract YYYY-07 columns in [start..end].
     * Returns map: columnName => year.
     */
    private function extractYearCols($keys, $start, $end)
    {
        $out = [];
        foreach ($keys as $col) {
            if (preg_match('/^(\d{4})-07$/', $col, $m)) {
                $year = intval($m[1]);
                if ($year >= $start && $year <= $end) {
                    $out[$col] = $year;
                }
            }
        }
        return $out;
    }
}
