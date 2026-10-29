<?php

use App\Http\Controllers\OrderController;
use Illuminate\Support\Facades\Route;

Route::middleware(['auth'])->group(function () {
    Route::get('/orders/{order}', [OrderController::class, 'show']);
});
