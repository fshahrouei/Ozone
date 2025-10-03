<?php

//use Illuminate\Support\Facades\Route;

// Authentication Routes
// Route::group([
//     'namespace' => '\App\Http\Controllers\API\V1\Auth',
//     'as' => 'api.auth.',
//     'prefix' => 'api/v1/auth'
// ], function () {
//     // /api/v1/auth/login
//     Route::post('login', ['as' => 'login', 'uses' => 'AuthController@login']);

//     // /api/v1/auth/logout
//     Route::post('logout', ['as' => 'logout', 'uses' => 'AuthController@logout'])->middleware('auth:api');

//     // /api/v1/auth/register
//     Route::post('register', ['as' => 'register', 'uses' => 'AuthController@register']);

//     // /api/v1/auth/verify-email
//     Route::post('verify-email', ['as' => 'verify-email', 'uses' => 'AuthController@verifyEmail']);

//     // /api/v1/auth/forgot-password
//     Route::post('forgot-password', ['as' => 'forgot-password', 'uses' => 'AuthController@forgotPassword']);

//     // /api/v1/auth/reset-password
//     Route::post('reset-password', ['as' => 'reset-password', 'uses' => 'AuthController@resetPassword']);

//     // /api/v1/auth/me
//     Route::get('me', ['as' => 'me', 'uses' => 'AuthController@me'])->middleware('auth:api');
// });
