<?php
use Illuminate\Support\Facades\Route;

Route::group([
    'namespace' => '\App\Http\Controllers\API\V1\Frontend',
    'as' => 'api.v1.frontend.settings.',
    //'middleware' => ['api','auth:api'],
    'middleware' => [],
    'prefix' => 'v1/frontend/settings'
], function () {

    // /api/v1/frontend/settings/checkUpdate
    // Check for app updates (version, mandatory flag, download links)
    Route::get('checkUpdate', ['as' => 'checkUpdate', 'uses' => 'FrontendController@checkUpdate']);

    // /api/v1/frontend/settings/about
    // Get "About" page data
    Route::get('about', ['as' => 'about', 'uses' => 'FrontendController@about']);
});
