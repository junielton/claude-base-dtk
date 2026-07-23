<?php

use App\Http\Controllers\InvoiceController;
use App\Http\Controllers\OrderController;
use App\Http\Controllers\UserController;
use Illuminate\Support\Facades\Route;

Route::middleware(['auth'])->group(function () {
    Route::get('/orders', [OrderController::class, 'index']);

    Route::middleware([\App\Http\Middleware\EnsureOrderOwner::class])->group(function () {
        Route::get('/orders/{order}', [OrderController::class, 'show']);
        Route::post('/orders/{order}/ship', [OrderController::class, 'ship']);
    });

    Route::get('/invoices/{invoice}', [InvoiceController::class, 'show']);
    Route::get('/invoices/{invoice}/receipt', [InvoiceController::class, 'receipt']);
    Route::post('/invoices', [InvoiceController::class, 'store']);
    Route::get('/users/search', [UserController::class, 'search']);
    Route::get('/users/{user}', [UserController::class, 'show']);
});
