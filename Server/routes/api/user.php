<?php
use Illuminate\Support\Facades\Route;

Route::group([
    'namespace' => '\App\Http\Controllers\API\V1\Frontend',
    'as' => 'api.backend.',
    //'middleware' => ['api'], // Disable authentication here if needed
    'prefix' => 'users3/'
], function () {
    // Example test route (disabled)
    // Route::get('users/index', ['as' => 'users.index', 'uses' => 'UsersController@index']);
});


Route::group([
    'namespace' => '\App\Http\Controllers\API\V1\Backend',
    'as' => 'api.v1.backend.users.',
    //'middleware' => ['api','auth:api'],
    'middleware' => ['api', 'auth:api', 'can:view-users'], // Requires API auth + permission to view users
    'prefix' => 'v1/backend/users'
], function () {

    // /api/v1/backend/users/index
    // Get list of users (requires authentication & authorization)
    Route::get('index', ['as' => 'index', 'uses' => 'UsersController@index']);

    // Example test route (disabled)
    // Route::get('index', function () {
    //     return response()->json(['message' => 'This route is working!']);
    // });
});
