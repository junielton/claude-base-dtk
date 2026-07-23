<?php

namespace App\Events;

use App\Models\Order;

class OrderShipped
{
    public function __construct(public Order $order)
    {
    }
}
