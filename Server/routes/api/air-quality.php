<?php
use App\Http\Controllers\API\V1\Frontend\AirQualitiesController;
use Illuminate\Support\Facades\Route;

Route::group([
    'prefix' => 'v1/frontend/air-quality',              // API prefix (kebab-case + singular)
    'as' => 'api.v1.frontend.air-quality.',             // Route name prefix (aligned with URL)
    'middleware' => ['api'],
], function () {

    // /api/v1/frontend/air-quality/get-tempo-data
    Route::get('get-tempo-data', [AirQualitiesController::class, 'getTempoData'])->name('getTempoData');

    // /api/v1/frontend/air-quality/app-status
    Route::get('app-status', [AirQualitiesController::class, 'appStatus'])->name('appStatus');

    // /api/v1/frontend/air-quality/overlays?product=no2&z=3&v=G3683552335-LARC_CLOUD
    Route::get('overlays', [AirQualitiesController::class, 'overlays'])->name('overlays');

    // /api/v1/frontend/air-quality/overlay-times?product=no2&days=3&order=asc
    Route::get('overlay-times', [AirQualitiesController::class, 'overlayTimes'])->name('overlay-times');

    // /api/v1/frontend/air-quality/legend?product=no2
    // /api/v1/frontend/air-quality/legend?product=o3tot
    // /api/v1/frontend/air-quality/legend?product=cldo4&nocache=1
    Route::get('legend', [AirQualitiesController::class, 'legend'])->name('legend');

    // /api/v1/frontend/air-quality/forecast
    Route::get('forecast', [AirQualitiesController::class, 'forecast'])->name('forecast');
    // /api/v1/frontend/air-quality/forecast-times
    //Route::get('forecast-times', [AirQualitiesController::class, 'forecastTimes'])->name('forecastTimes'); // optional

    // /api/v1/frontend/air-quality/overlay-grids
    Route::get('overlay-grids', [AirQualitiesController::class, 'overlayGrids'])->name('overlayGrids');

    // /api/v1/frontend/air-quality/forecast-grids
    Route::get('forecast-grids', [AirQualitiesController::class, 'forecastGrids'])->name('forecastGrids');

    // /api/v1/frontend/air-quality/point-assess
    Route::get('point-assess', [AirQualitiesController::class, 'PointAssess'])->name('PointAssess');

    // /api/v1/frontend/air-quality/stations
    Route::get('stations', [AirQualitiesController::class, 'Stations'])->name('Stations');
});
