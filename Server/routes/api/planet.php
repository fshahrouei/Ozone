<?php
use Illuminate\Support\Facades\Route;

Route::group([
    'namespace' => '\App\Http\Controllers\API\V1\Frontend',
    'as' => 'api.v1.frontend.planets.',
    //'middleware' => ['api','auth:api'],
    'middleware' => [],
    'prefix' => 'v1/frontend/planets'
], function () {

    // /api/v1/frontend/planets/index
    // Get list of all planets
    Route::get('index', ['as' => 'index', 'uses' => 'PlanetsController@index']);

    // /api/v1/frontend/planets/show/{id}
    // Get detailed info for a specific planet by ID
    Route::get('show/{id}', ['as' => 'show', 'uses' => 'PlanetsController@show']);

    // /api/v1/frontend/planets/questions/{id}
    // Get questions related to a specific planet by ID
    Route::get('questions/{id}', ['as' => 'questions', 'uses' => 'PlanetsController@questions']);

    // Example test route (disabled)
    // Route::get('index', function () {
    //     return response()->json(['message' => 'This route is working!']);
    // });
});
