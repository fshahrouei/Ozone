<?php
use Illuminate\Support\Facades\Route;

Route::group([
    'namespace' => '\App\Http\Controllers\API\V1\Frontend',
    'as' => 'api.v1.frontend.posts.',
    //'middleware' => ['api','auth:api'],
    'middleware' => [],
    'prefix' => 'v1/frontend/posts'
], function () {

    // /api/v1/frontend/posts/index
    // Get list of all posts
    Route::get('index', ['as' => 'index', 'uses' => 'PostsController@index']);

    // /api/v1/frontend/posts/show/{id}
    // Get detailed info for a specific post by ID
    Route::get('show/{id}', ['as' => 'show', 'uses' => 'PostsController@show']);

    // Example test route (disabled)
    // Route::get('index', function () {
    //     return response()->json(['message' => 'This route is working!']);
    // });
});
