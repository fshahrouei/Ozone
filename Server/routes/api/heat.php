<?php
use Illuminate\Support\Facades\Route;

Route::group([
    'namespace' => '\App\Http\Controllers\API\V1\Frontend',
    'as' => 'api.v1.frontend.heats.',
    //'middleware' => ['api','auth:api'],
    'middleware' => [],
    'prefix' => 'v1/frontend/heats'
], function () {

    // /api/v1/frontend/heats/climate-anomalies
    // Get climate anomalies data
    Route::get('climate-anomalies', ['as' => 'climate-anomalies', 'uses' => 'HeatsController@climateAnomalies']);

    // /api/v1/frontend/heats/countries/{year?}
    // Get all countries data (optionally by year)
    Route::get('countries/{year?}', ['as' => 'countries', 'uses' => 'HeatsController@countries']);

    // /api/v1/frontend/heats/country/{iso_a3}/{year?}
    // Get data for a single country (by ISO_A3 code and optional year)
    Route::get('country/{iso_a3}/{year?}', ['as' => 'country', 'uses' => 'HeatsController@country']);

    // /api/v1/frontend/heats/years
    // Get available years list
    Route::get('years', ['as' => 'years', 'uses' => 'HeatsController@years']);

    // /api/v1/frontend/heats/statistics/{year?}
    // Get statistics (optionally filtered by year)
    Route::get('statistics/{year?}', ['as' => 'statistics', 'uses' => 'HeatsController@statistics']);
});
