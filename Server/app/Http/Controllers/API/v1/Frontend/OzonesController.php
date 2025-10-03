<?php

namespace App\Http\Controllers\API\V1\Frontend;

use Illuminate\Support\Str;
use App\Http\Controllers\API\V1\Frontend\FrontendBaseController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Log;

class OzonesController extends FrontendBaseController
{
    public function __construct()
    {
        parent::__construct();
        // Base controller metadata (kept intact; used by shared frontend scaffolding)
        $this->var['model_type'] = 'post';
        $this->var['model_name'] = 'posts';
        $this->var['model_api'] = 'ozones';
        $this->var['model_name_singular'] = Str::singular($this->var['model_name']);
        $this->var['model_class'] = 'App\Models\Post';
        $this->var['model_icon'] = '<i class="iconix icon-book"></i>';
        $this->var['model_view'] = $this->var['model_framework'] . '.frontend.' . $this->var['model_name'];
        $this->var['breadcrumbs'][route('frontend.home')] = __('panel.page_user');
        // $this->var['breadcrumbs'][route('frontend.posts.index')] = __('panel.posts');

        // Whitelists for index/show payloads (if used by base controller)
        $this->var['model_index_fields'] = ['id', 'name', 'description', 'thumbnail'];
        $this->var['model_show_fields'] = ['id', 'name', 'description', 'thumbnail', 'body', 'attributes'];
        $this->var['model_quiz_fields'] = ['id', 'name', 'quizzes'];
    }

    /**
     * Validation rules selector for various controller operations.
     * Currently returns empty or minimal rules; extend as needed.
     */
    public function getRules($params)
    {
        $type = $params['type'] ?? 'index';
        $input = $params['input'] ?? [];
        $model_name = $params['model_name'] ?? null;
        $model_name_singular = $params['model_name_singular'] ?? null;
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
     * Convert ISO 3166-1 alpha-3 to alpha-2 (lowercase).
     * Returns $fallback (or null) if not found.
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

            // Territories / special cases (non-ISO or deprecated kept for robustness)
            'XKX' => 'xk', // Kosovo (non-ISO; used by EU/IMF/World Bank)
            'ANT' => 'an', // Netherlands Antilles (deprecated; split to CW, SX, BQ in 2010)
        ];

        $key = strtoupper(trim($iso3));
        return $MAP[$key] ?? $fallback;
    }

    // ---- Examples ----
    /*
    echo iso3_to_iso2_lower('IRN'); // ir
    echo iso3_to_iso2_lower('usa'); // us
    echo iso3_to_iso2_lower('XKX'); // xk
    echo iso3_to_iso2_lower('ZZZ', '??'); // ??
    */

    /**
     * Map total emissions to a discrete score (1..10) for visualization.
     * Buckets are heuristic and can be tuned.
     */
    function calculateScore($totalEmissions)
    {
        if ($totalEmissions >= 10000000000) {
            return 10;
        } elseif ($totalEmissions >= 3000000000) {
            return 9;
        } elseif ($totalEmissions >= 1000000000) {
            return 8;
        } elseif ($totalEmissions >= 300000000) {
            return 7;
        } elseif ($totalEmissions >= 100000000) {
            return 6;
        } elseif ($totalEmissions >= 30000000) {
            return 5;
        } elseif ($totalEmissions >= 10000000) {
            return 4;
        } elseif ($totalEmissions >= 3000000) {
            return 3;
        } elseif ($totalEmissions >= 1000000) {
            return 2;
        } else {
            return 1;
        }
    }

    /**
     * GET /api/v1/frontend/ozones/countries/{year?}
     * Build a per-country list for {year} with total emissions and score.
     */
    public function countries(Request $request, $year = 2023)
    {
        // Sources:
        // - https://ourworldindata.org/grapher/total-ghg-emissions
        // - https://ourworldindata.org/grapher/ghg-emissions-by-gas

        $year = $request->query('year', $year);

        $csvFile  = storage_path('app/dl/json/ghg.csv'); // Input CSV path
        $jsonFile = '/dl/json/ghg.json';                 // Output JSON path (not used here)

        $years_limit = [$year];   // Example: a single target year
        $reauired    = ['iso_a3']; // Required fields (typo kept as-is to avoid logic change)

        // Re-map a subset of CSV columns to our keys
        $newHeaders = [
            // 1 => 'name',  // 1 -> 'Entity'
            2 => 'iso_a3',   // 2 -> (was commented/empty in some sources)
            // 3 => 'year',
            // 4 => 'n2o',    // Annual nitrous oxide emissions (CO2e)
            // 5 => 'ch4',    // Annual methane emissions (CO2e)
            // 6 => 'co2',    // Annual CO2 emissions
            7 => 'total',    // Computed: total emissions
            8 => 'score'     // Computed: score bucket
        ];

        // Pretty-printer for emission numbers
        $formatEmission = function ($value) {
            if ($value == 0) return '0 t';
            if ($value < 1000000) return $value . ' t';
            if ($value < 1000000000) return round($value / 1000000, 2) . ' million t';
            return round($value / 1000000000, 2) . ' billion t';
        };

        $csvData = array_map('str_getcsv', file($csvFile));
        $headers = array_shift($csvData);

        $yearlyData = [];

        foreach ($csvData as $row) {
            $_year = (int)$row[2];

            if ($_year < $years_limit[0] || $_year > $years_limit[count($years_limit) - 1]) {
                continue;
            }

            $totalEmissions = (float)$row[3] + (float)$row[4] + (float)$row[5];
            $score = self::calculateScore($totalEmissions);

            $row[] = $totalEmissions;
            $row[] = $score;

            // Ensure required fields exist
            $addRow = true;
            foreach ($reauired as $requiredField) {
                $index = array_search($requiredField, $newHeaders);
                if ($index !== false && empty($row[$index - 1])) {
                    $addRow = false;
                    break;
                }
            }
            if (!$addRow) continue;

            $mappedRow = [];
            foreach ($newHeaders as $index => $header) {
                if ($header === null || empty($row[$index - 1])) continue;

                if (in_array($header, ['n2o', 'ch4', 'co2', 'total'])) {
                    $mappedRow[$header] = $formatEmission((float)$row[$index - 1]);
                } else {
                    $mappedRow[$header] = $row[$index - 1];
                }
            }

            if (count($years_limit) === 1) {
                $yearlyData[] = $mappedRow;
            } else {
                if (!isset($yearlyData[$_year])) $yearlyData[$_year] = [];
                $yearlyData[$_year][] = $mappedRow;
            }
        }

        return response()->json([
            'succeed'      => true,
            'status'       => 200,
            'message'      => 'Operation successful.',
            'current_year' => $year,
            'data'         => $yearlyData,
        ], 200, ['Content-Type' => 'application/json; charset=UTF-8'], JSON_UNESCAPED_UNICODE);
    }

    /**
     * GET /api/v1/frontend/ozones/country/{ISO3}/{year?}
     * Detailed slice for a single country at {year}, with ranking context.
     */
    public function country(Request $request, $iso_a3, $year = 2023)
    {
        $iso_a3 = trim($iso_a3);

        // Filter list of aggregate regions/entities to exclude from country stats (UPPERCASE)
        $filter = [
            'WORLD',
            'AFRICA',
            'ASIA',
            'EUROPE',
            'NORTHAMERICA',
            'SOUTHAMERICA',
            'OCEANIA',
            'OWID_WRL',
            'OWID_AFR',
            'OWID_ASI',
            'OWID_EUR',
            'OWID_NAM',
            'OWID_SAM',
            'OWID_OCE'
        ];

        $iso_a3_upper = strtoupper($iso_a3);

        // Abort if country code is empty or belongs to the excluded list
        if (empty($iso_a3_upper) || in_array($iso_a3_upper, $filter)) {
            return response()->json([
                'succeed'  => false,
                'status'   => 404,
                'message'  => 'Selected country is invalid or the country code is empty.',
                'iso_a3'   => $iso_a3,
                'year'     => $year,
                'country'  => null,
            ], 404, ['Content-Type' => 'application/json; charset=UTF-8'], JSON_UNESCAPED_UNICODE);
        }

        $csvFile = storage_path('app/dl/json/ghg.csv');
        $csvData = array_map('str_getcsv', file($csvFile));
        $headers = array_shift($csvData);

        $allCountries = [];
        $history = [];
        $countryData = null;

        foreach ($csvData as $row) {
            $_entity = $row[0];
            $_iso_a3 = strtoupper(trim($row[1]));
            $_year   = (int)$row[2];
            $n2o     = (float)$row[3];
            $ch4     = (float)$row[4];
            $co2     = (float)$row[5];
            $totalEmissions = $n2o + $ch4 + $co2;

            // 1) Skip if ISO3 is empty
            if (empty($_iso_a3)) {
                continue;
            }
            // 2) Skip aggregates defined in $filter
            if (in_array($_iso_a3, $filter)) {
                continue;
            }

            // Build country/current-year card + 25-year history for the target ISO3
            if ($_iso_a3 === $iso_a3_upper) {
                if ((int) $_year === (int) $year) {
                    // Default: no flag
                    $flag = null;

                    // iso_a3 -> iso_a2 (lowercase)
                    $_iso_a2 = self::iso3_to_iso2_lower($_iso_a3);

                    if (!empty($_iso_a2)) {
                        // Relative path inside public/ for the flag asset
                        $relativePath = "img/flags/1x1/{$_iso_a2}.svg";
                        $absolutePath = public_path($relativePath);

                        // If the file exists, build a public URL
                        if (file_exists($absolutePath)) {
                            $flag = asset($relativePath);
                        }
                        // (Optional) Fallback to PNG if SVG does not exist:
                        // else {
                        //     $relativePng = "img/flags/4x3/{$_iso_a2}.png";
                        //     if (file_exists(public_path($relativePng))) {
                        //         $flag = asset($relativePng);
                        //     }
                        // }
                    }

                    $countryData = [
                        'entity' => $_entity,
                        'iso_a3' => $_iso_a3,
                        'image'  => $flag,
                        'year'   => (int) $_year,
                        'n2o'    => (float) $n2o,
                        'ch4'    => (float) $ch4,
                        'co2'    => (float) $co2,
                        'total'  => (float) $totalEmissions,
                        'score'  => self::calculateScore($totalEmissions),
                    ];
                }

                // 25-year history (or less) up to the selected year
                if ($_year <= $year && $_year >= $year - 24) {
                    $history[] = [
                        'year'  => $_year,
                        'n2o'   => $n2o,
                        'ch4'   => $ch4,
                        'co2'   => $co2,
                        'total' => $totalEmissions,
                    ];
                }
            }

            // Build list of all countries at target year for ranking/others block
            if ($_year == $year) {
                $allCountries[] = [
                    'iso_a3' => $_iso_a3,
                    'name'   => $_entity,
                    'value'  => $totalEmissions,
                ];
            }
        }

        // If country/year slice not found
        if (!$countryData) {
            return response()->json([
                'succeed' => false,
                'status'  => 404,
                'message' => 'No data found for this country and year.',
                'iso_a3'  => $iso_a3,
                'year'    => $year,
                'country' => null,
            ], 404, ['Content-Type' => 'application/json; charset=UTF-8'], JSON_UNESCAPED_UNICODE);
        }

        // Sort all countries by total (desc)
        usort($allCountries, function ($a, $b) {
            return $b['value'] <=> $a['value'];
        });

        // Top 10 (ensure current country is included)
        $topCount     = 10;
        $topCountries = array_slice($allCountries, 0, $topCount);

        $countryInTop = false;
        foreach ($topCountries as $c) {
            if ($c['iso_a3'] === $iso_a3_upper) {
                $countryInTop = true;
                break;
            }
        }
        if (!$countryInTop) {
            // Include current country explicitly if not already in top list
            array_unshift($topCountries, [
                'iso_a3' => $countryData['iso_a3'],
                'name'   => $countryData['entity'],
                'value'  => $countryData['total'],
            ]);
            if (count($topCountries) > $topCount) {
                array_pop($topCountries);
            }
        }

        // Sum of all and of top N
        $total = array_reduce($allCountries, function ($carry, $item) {
            return $carry + $item['value'];
        }, 0.0);

        $topSum = array_reduce($topCountries, function ($carry, $item) {
            return $carry + $item['value'];
        }, 0.0);

        $others = [
            'value' => $total - $topSum,
        ];

        // Sort history ascending by year
        usort($history, function ($a, $b) {
            return $a['year'] <=> $b['year'];
        });

        return response()->json([
            'succeed'        => true,
            'status'         => 200,
            'message'        => 'Operation successful.',
            'iso_a3'         => $iso_a3,
            'year'           => $year,
            'country'        => $countryData,
            'top_countries'  => $topCountries,
            'others'         => $others,
            'total'          => $total,
            'history'        => $history,
        ], 200, ['Content-Type' => 'application/json; charset=UTF-8'], JSON_UNESCAPED_UNICODE);
    }

    /**
     * GET /api/v1/frontend/ozones/years
     * Return the available years detected in the CSV dataset.
     */
    public function years()
    {
        $csvFile     = storage_path('app/dl/json/ghg.csv'); // CSV input path
        $years_limit = [1850, 2030]; // Inclusive year range to consider

        $csvData = array_map('str_getcsv', file($csvFile));
        array_shift($csvData); // Drop header

        $years = [];
        foreach ($csvData as $row) {
            $_year = (int)$row[2]; // Column 3: year
            if ($_year >= $years_limit[0] && $_year <= $years_limit[1]) {
                $years[] = $_year;
            }
        }

        // Deduplicate and sort ascending
        $years = array_values(array_unique($years));
        sort($years);

        return response()->json([
            'succeed' => true,
            'status'  => 200,
            'message' => 'Operation successful.',
            'data'    => $years,
            // 'default_year' => 2023,
        ], 200, ['Content-Type' => 'application/json; charset=UTF-8'], JSON_UNESCAPED_UNICODE);
    }

    /**
     * GET /api/v1/frontend/ozones/statistics/{year?}
     * Build top-10 emitters and a 25-year history for top countries + Others.
     * Supports excluding aggregates via ?exclude=world,africa,asia,EU28
     */
    public function statistics(Request $request, $year = 2023)
    {
        // Selected year and 25-year window
        $year = (int)$request->query('year', $year);
        $history_years = range($year - 24, $year);

        // CSV source
        $csvFile = storage_path('app/dl/json/ghg.csv');
        if (!file_exists($csvFile)) {
            return response()->json(['error' => 'CSV file not found'], 500);
        }
        $csvData = array_map('str_getcsv', file($csvFile));
        if (!$csvData || count($csvData) < 2) {
            return response()->json(['error' => 'CSV file is empty or invalid'], 500);
        }

        // Extract header row
        $headers = array_shift($csvData);

        // ------------------ Country filter ------------------
        // Default internal exclusions (customize as needed)
        $defaultFilter = ['world', 'africa', 'asia'];

        // Optional query override: ?exclude=world,africa,asia,EU28
        $excludeParam = trim((string)$request->query('exclude', ''));
        $excludeListFromQuery = $excludeParam === '' ? [] : array_map('trim', explode(',', $excludeParam));

        // Merge + unique + lowercase
        $filterRaw  = array_values(array_unique(array_filter(array_merge($defaultFilter, $excludeListFromQuery), fn($x) => $x !== '')));
        $filterNorm = array_map(fn($s) => mb_strtolower($s), $filterRaw);

        // ------------------ Convert CSV to normalized structure ------------------
        $allData = [];
        foreach ($csvData as $row) {
            // Expected: name, iso_a3, year, n2o, ch4, co2
            if (count($row) < 6) continue;

            $_name = (string)$row[0];
            $_iso  = trim((string)$row[1]);
            $_year = (int)$row[2];

            // Skip if ISO3 missing/short/whitespace-only
            if ($_iso === '' || strlen($_iso) < 3) {
                continue;
            }

            // Skip if in the exclusion list (by name or ISO3)
            $nameNorm = mb_strtolower($_name);
            $isoNorm  = mb_strtolower($_iso);
            if (in_array($nameNorm, $filterNorm, true) || in_array($isoNorm, $filterNorm, true)) {
                continue;
            }

            // Parse numeric fields (fallback to 0 if missing)
            $_n2o = is_numeric($row[3]) ? (float)$row[3] : 0.0;
            $_ch4 = is_numeric($row[4]) ? (float)$row[4] : 0.0;
            $_co2 = is_numeric($row[5]) ? (float)$row[5] : 0.0;
            $total = $_n2o + $_ch4 + $_co2;

            if (!isset($allData[$_iso])) {
                $allData[$_iso] = [
                    'name'   => $_name,
                    'iso_a3' => $_iso,
                    'values' => [],
                ];
            }
            $allData[$_iso]['values'][$_year] = [
                'year'  => $_year,
                'n2o'   => $_n2o,
                'ch4'   => $_ch4,
                'co2'   => $_co2,
                'total' => $total,
            ];
        }

        // ------------------ Top 10 countries for the selected year ------------------
        $countriesForYear = [];
        foreach ($allData as $iso => $country) {
            if (isset($country['values'][$year])) {
                $countriesForYear[] = [
                    'iso_a3' => $iso,
                    'name'   => $country['name'],
                    'value'  => (float)$country['values'][$year]['total'],
                ];
            }
        }

        if (empty($countriesForYear)) {
            return response()->json([
                'year'          => $year,
                'top_countries' => [],
                'others'        => ['value' => 0],
                'total'         => 0,
                'history'       => [],
                'excluded'      => $filterRaw,
            ], 200, ['Content-Type' => 'application/json; charset=UTF-8'], JSON_UNESCAPED_UNICODE);
        }

        // Sort descending by total
        usort($countriesForYear, fn($a, $b) => $b['value'] <=> $a['value']);

        // Take top 10
        $topCountries = array_slice($countriesForYear, 0, 10);

        // Sum of all others beyond top 10
        $otherSum = array_sum(array_map(
            fn($c, $idx) => $idx < 10 ? 0.0 : (float)$c['value'],
            $countriesForYear,
            array_keys($countriesForYear)
        ));

        // ------------------ Build 25-year history for top countries + Others ------------------
        $history = [];

        // History for each top country
        foreach ($topCountries as $country) {
            $iso = $country['iso_a3'];
            $values = [];
            foreach ($history_years as $hYear) {
                $v = isset($allData[$iso]['values'][$hYear]) ? (float)$allData[$iso]['values'][$hYear]['total'] : 0.0;
                $values[] = ['year' => $hYear, 'value' => $v];
            }
            $history[] = [
                'iso_a3' => $iso,
                'name'   => $allData[$iso]['name'],
                'values' => $values,
            ];
        }

        // History for Others
        $others_values = [];
        foreach ($history_years as $hYear) {
            $sum = 0.0;
            foreach ($countriesForYear as $idx => $c) {
                if ($idx >= 10) {
                    $iso = $c['iso_a3'];
                    $v = isset($allData[$iso]['values'][$hYear]) ? (float)$allData[$iso]['values'][$hYear]['total'] : 0.0;
                    $sum += $v;
                }
            }
            $others_values[] = ['year' => $hYear, 'value' => $sum];
        }
        $history[] = [
            'iso_a3' => 'OTH',
            'name'   => 'Other',
            'values' => $others_values,
        ];

        // Totals
        $topSum     = array_sum(array_map(fn($c) => (float)$c['value'], $topCountries));
        $grandTotal = $topSum + (float)$otherSum;

        return response()->json([
            'year'          => $year,
            'top_countries' => array_map(fn($c) => [
                'iso_a3' => $c['iso_a3'],
                'name'   => $c['name'],
                'value'  => (float)$c['value'],
            ], $topCountries),
            'others'        => ['value' => (float)$otherSum],
            'total'         => (float)$grandTotal,
            'history'       => $history,
            'excluded'      => $filterRaw, // Transparency: list of excluded aggregates
        ], 200, ['Content-Type' => 'application/json; charset=UTF-8'], JSON_UNESCAPED_UNICODE);
    }

    /**
     * GET /api/v1/frontend/ozones/generate-geojson
     * Minify/reshape an existing GeoJSON into a simplified FeatureCollection.
     */
    public function generateGeoJson()
    {
        // Reference: https://geojson-maps.kyd.au/
        // Input and output file paths
        $inputFile  = storage_path('app/dl/json/old_globe.json');
        $outputFile = storage_path('app/dl/json/new_globe.json');
        // $outputFile = 'dl/json/new_globe.json';

        // Validate input existence
        if (!file_exists($inputFile)) {
            return response()->json(['error' => 'Input file does not exist at ' . $inputFile], 400);
        }

        // Validate output directory writability
        if (!is_writable(dirname($outputFile))) {
            return response()->json(['error' => 'Output directory is not writable.'], 400);
        }

        // Read and decode input JSON
        $jsonData = File::get($inputFile);
        $data = json_decode($jsonData, true);

        if ($data === null) {
            return response()->json(['error' => 'Invalid JSON in the input file.'], 400);
        }

        // Prepare minimized structure
        $minifiedData = [
            'type' => 'FeatureCollection',
            'features' => []
        ];

        // Extract essentials from each feature (names, ISO3, optional label coords)
        foreach ($data['features'] as $feature) {
            $minifiedData['features'][] = [
                'type' => 'Feature',
                'properties' => [
                    'name_en' => $feature['properties']['name_en'] ?? null,
                    'name_fa' => $feature['properties']['name_fa'] ?? null,
                    'iso_a3'  => $feature['properties']['iso_a3'] ?? null,
                    // 'iso_a2' => $feature['properties']['iso_a2'] ?? null,
                    'label_x' => $feature['properties']['label_x'] ?? null,
                    'label_y' => $feature['properties']['label_y'] ?? null,
                    // 'min_zoom' => $feature['properties']['min_zoom'] ?? null,
                    // 'max_zoom' => $feature['properties']['max_zoom'] ?? null,
                ],
                'geometry' => $feature['geometry'] ?? null
            ];
        }

        // Encode JSON without escaping Unicode/slashes
        $minifiedJson = json_encode($minifiedData, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

        // Debug log (optional; remove or lower level in production)
        Log::debug('Minified JSON Data: ' . $minifiedJson);

        // Persist to disk
        $fileSaved = File::put($outputFile, $minifiedJson);

        if (!$fileSaved) {
            return response()->json(['error' => 'Failed to write to output file.'], 500);
        }

        return 'File generated successfully!';

        // Unreachable (kept to preserve original structure)
        return response()->json(['message' => 'File generated successfully!', 'file' => $outputFile]);
    }
}
