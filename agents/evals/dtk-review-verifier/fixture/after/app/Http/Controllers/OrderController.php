<?php

namespace App\Http\Controllers;

use App\Events\OrderShipped;
use App\Models\Order;
use Illuminate\Http\Request;

class OrderController extends Controller
{
    public function index(Request $request)
    {
        $orders = Order::where('user_id', $request->user()->id)->get();

        $rows = [];

        foreach ($orders as $order) {
            $rows[] = [
                'id' => $order->id,
                'warehouse' => $order->warehouse->name,
            ];
        }

        return response()->json($rows);
    }

    public function show(Order $order)
    {
        return response()->json([
            'id' => $order->id,
            'total' => $order->total_cents,
            'shipped_at' => $order->shipped_at,
        ]);
    }

    public function ship(Order $order)
    {
        $order->update(['shipped_at' => now()]);

        event(new OrderShipped($order));

        return response()->json(['ok' => true]);
    }
}
