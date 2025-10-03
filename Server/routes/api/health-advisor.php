<?php
use App\Http\Controllers\API\V1\Frontend\HealthAdvisorController;
use Illuminate\Support\Facades\Route;

Route::group([
    'prefix' => 'v1/frontend/health-advisor',   // API prefix (kebab-case + singular)
    'as' => 'api.v1.frontend.health-advisor.',  // Route name prefix
    'middleware' => ['api'],
], function () {

    // /api/v1/frontend/health-advisor/store
    // Create or update a record
    Route::post('store', [HealthAdvisorController::class, 'store'])->name('store');

    // /api/v1/frontend/health-advisor/index
    // List all records (GET request)
    Route::get('index', [HealthAdvisorController::class, 'index'])->name('index');

    // /api/v1/frontend/health-advisor/destroy/{id}
    // Delete a record by ID or UUID (DELETE request)
    Route::delete('destroy/{id}', [HealthAdvisorController::class, 'destroy'])->name('destroy');

    // /api/v1/frontend/health-advisor/notifications
    // Fetch related notifications
    Route::get('notifications', [HealthAdvisorController::class, 'notifications'])->name('notifications');
});
