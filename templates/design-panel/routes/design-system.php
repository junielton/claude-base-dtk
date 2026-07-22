<?php

use App\Http\Controllers\DesignSystem\PanelController;
use App\Http\Controllers\DesignSystem\PreviewController;
use App\Http\Middleware\EnsureDesignSystemEnabled;
use Illuminate\Support\Facades\Route;

Route::middleware(EnsureDesignSystemEnabled::class)->group(function () {
    Route::get('/design-system/preview/{area}/{item}', PreviewController::class)
        ->name('design-system.preview');

    Route::get('/design-system/{area?}/{item?}', PanelController::class)
        ->name('design-system');
});
