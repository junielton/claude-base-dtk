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

    public function lookup(string $reference)
    {
        $order = Order::findByReference($reference) ?? abort(404);

        return response()->json(['id' => $order->id, 'status' => $order->status]);
    }
}
