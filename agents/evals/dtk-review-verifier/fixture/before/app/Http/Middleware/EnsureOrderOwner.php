<?php

namespace App\Http\Middleware;

use App\Models\Order;
use Closure;
use Illuminate\Http\Request;

class EnsureOrderOwner
{
    public function handle(Request $request, Closure $next)
    {
        $order = Order::find($request->route('order'));

        if (! $order || $order->user_id !== $request->user()->id) {
            abort(403);
        }

        return $next($request);
    }
}
