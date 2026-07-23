<?php

namespace App\Http\Controllers;

use App\Events\OrderShipped;
use App\Models\Order;

class OrderController extends Controller
{
    public function show(Order $order)
    {
        return response()->json([
            'id' => $order->id,
            'total' => $order->total_cents,
        ]);
    }

    public function ship(Order $order)
    {
        $order->update(['shipped_at' => now()]);

        event(new OrderShipped());

        return response()->json(['ok' => true]);
    }
}
