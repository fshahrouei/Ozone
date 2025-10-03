<?php
use Illuminate\Support\Facades\Route;

Route::group([
    'namespace' => '\App\Http\Controllers\API\V1\Frontend',
    'as' => 'api.v1.frontend.ozones.',
    //'middleware' => ['api','auth:api'],
    'middleware' => [],
    'prefix' => 'v1/frontend/ozones'
], function () {

    // /api/v1/frontend/ozones/countries/{year?}
    // Get ozone data for all countries (optionally filtered by year)
    Route::get('countries/{year?}', ['as' => 'countries', 'uses' => 'OzonesController@countries']);
    
    // /api/v1/frontend/ozones/country/{iso_a3}/{year?}
    // Get ozone data for a single country (by ISO_A3 code and optional year)
    Route::get('country/{iso_a3}/{year?}', ['as' => 'country', 'uses' => 'OzonesController@country']);

    // /api/v1/frontend/ozones/years
    // Get available years for ozone dataset
    Route::get('years', ['as' => 'years', 'uses' => 'OzonesController@years']);

    // /api/v1/frontend/ozones/statistics/{year?}
    // Get ozone statistics (optionally filtered by year)
    Route::get('statistics/{year?}', ['as' => 'statistics', 'uses' => 'OzonesController@statistics']);

    // /api/v1/frontend/ozones/generateGeoJson
    // Generate GeoJSON representation of ozone data
    Route::get('generateGeoJson', ['as' => 'generateGeoJson', 'uses' => 'OzonesController@generateGeoJson']);
});
