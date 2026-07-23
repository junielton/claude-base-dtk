<?php

use App\Http\Controllers\OrderController;
use App\Http\Controllers\UserController;
use Illuminate\Support\Facades\Route;

Route::middleware(['auth'])->group(function () {
    Route::middleware([\App\Http\Middleware\EnsureOrderOwner::class])->group(function () {
        Route::get('/orders/{order}', [OrderController::class, 'show']);
        Route::post('/orders/{order}/ship', [OrderController::class, 'ship']);
    });

    Route::get('/users/{user}', [UserController::class, 'show']);
});
