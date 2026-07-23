<?php

namespace App\Legacy;

use App\Models\Order;

class ReportBuilder
{
    public function monthlyTotals(): array
    {
        $rows = [];

        foreach (Order::all() as $order) {
            $rows[] = [
                'id' => $order->id,
                'customer' => $order->customer->name,
                'total' => $order->total_cents,
            ];
        }

        return $rows;
    }
}
