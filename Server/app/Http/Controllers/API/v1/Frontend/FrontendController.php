<?php

namespace App\Http\Controllers\API\V1\Frontend;

use App;
use URL;
use Illuminate\Http\Request;
use App\Http\Controllers\API\V1\Frontend\FrontendBaseController;
// use SEOMeta;
// use OpenGraph;
// use Twitter;

class FrontendController extends FrontendBaseController
{
    public function __construct()
    {
        parent::__construct();
        $this->var['model_view'] = $this->var['model_framework'] . '.frontend';
    }
    /**
     * Show the application dashboard.
     *
     * @return \Illuminate\Http\Response
     */

    public function checkUpdate(Request $request)
    {
        // Extract variables from $this->var if needed
        foreach ($this->var as $key => $value) {
            $$key = $value;
        }

        // Sample data representing the latest version and download links
        // (In production, fetch dynamically from DB, config, or a version file)
        $latestVersion = '2.0.0';
        $mandatoryUpdate = true;  // Indicates whether the update is mandatory

        // Define download links dynamically (demo values shown)
        $downloadLinks = [
            [
                'name' => 'Google Play',
                'link' => 'https://play.google.com/store/apps/details?id=cloud.dinamit.neon'
            ],
            [
                'name' => 'Direct Download',
                'link' => 'https://vivalavida.ir'
            ],
            // You can add more links here dynamically or based on a database query
            [
                'name' => 'App Store',
                'link' => 'https://www.apple.com/app-store/'
            ],
            [
                'name' => 'Website',
                'link' => 'https://example.com/download'
            ]
        ];

        // Compare client's current version with the latest version
        // Client is expected to send 'current_version' in the request
        $currentVersion = $request->input('current_version', '1.0.0'); // Default if not provided

        // If already up-to-date, return early
        if ($currentVersion == $latestVersion) {
            return response()->json([
                'succeed' => true,
                'status' => 200,
                'message' => 'You have the latest version.',
                'data' => null,
            ], 200, ['Content-Type' => 'application/json; charset=UTF-8'], JSON_UNESCAPED_UNICODE);
        }

        // Otherwise, return latest version info and download links
        return response()->json([
            'succeed' => true,
            'status' => 200,
            'message' => 'New update available.',
            'data' => [
                'latest_version' => $latestVersion,
                'mandatory_update' => $mandatoryUpdate,
                'download_links' => $downloadLinks // Dynamic links
            ],
        ], 200, ['Content-Type' => 'application/json; charset=UTF-8'], JSON_UNESCAPED_UNICODE);
    }

    public function about(Request $request)
    {
        // Extract variables from $this->var if needed
        foreach ($this->var as $key => $value) {
            $$key = $value;
        }

        // Sample data for the latest version (fetch dynamically in production)
        $latestVersion = '2.0.0';

        $downloadLinks = [
            [
                'name' => 'Google Play',
                'link' => 'https://play.google.com/store/apps/details?id=cloud.dinamit.neon'
            ],
            [
                'name' => 'Direct Download',
                'link' => 'https://vivalavida.ir'
            ],
            // You can add more links here dynamically or based on a database query
            [
                'name' => 'App Store',
                'link' => 'https://www.apple.com/app-store/'
            ],
            [
                'name' => 'Website',
                'link' => 'https://example.com/download'
            ]
        ];

        $team_members = [
            [
                'name' => 'Ali Raha',
                'role' => 'Lead Developer',
                'imageUrl' => url('/img/demo/pics/planets/moon.webp'),
                'instagramUrl' => '/',
                'facebookUrl' => null,
                'twitterUrl' => null,
                'telegramUrl' => null,
            ],
            [
                'name' => 'Ali Raha',
                'role' => 'Lead Developer',
                'imageUrl' => url('/img/demo/pics/planets/moon.webp'),
                'instagramUrl' => '/',
                'facebookUrl' => null,
                'twitterUrl' => null,
                'telegramUrl' => null,
            ],
            [
                'name' => 'Ali Raha',
                'role' => 'Lead Developer',
                'imageUrl' => url('/img/demo/pics/planets/moon.webp'),
                'instagramUrl' => '/',
                'facebookUrl' => null,
                'twitterUrl' => null,
                'telegramUrl' => null,
            ]
        ];

        return response()->json([
            'succeed' => true,
            'status' => 200,
            'message' => 'New update available.',
            'data' => [
                'latest_version' => $latestVersion,
                'downloadLinks' => $downloadLinks, // Dynamic links
                'team_members' => $team_members     // Dynamic team list
            ],
        ], 200, ['Content-Type' => 'application/json; charset=UTF-8'], JSON_UNESCAPED_UNICODE);
    }
}
