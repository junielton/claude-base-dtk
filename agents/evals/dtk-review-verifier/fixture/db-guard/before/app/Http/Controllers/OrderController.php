<?php

namespace App\Http\Controllers;

use App\Models\Order;

class OrderController extends Controller
{
    public function show(Order $order)
    {
        return response()->json([
            'id' => $order->id,
            'status' => $order->status,
            'total' => $order->total_cents,
        ]);
    }
}
