<?php

namespace Tests\Feature;

use App\Models\Order;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class OrderLookupTest extends TestCase
{
    use RefreshDatabase;

    public function test_lookup_ignores_the_case_the_customer_typed(): void
    {
        Order::create(['reference' => 'ACM-1042', 'customer_id' => 1, 'total_cents' => 4990]);

        $this->assertNotNull(Order::findByReference('acm-1042'));
        $this->assertNotNull(Order::findByReference(' ACM-1042 '));
    }

    public function test_an_unknown_reference_finds_nothing(): void
    {
        $this->assertNull(Order::findByReference('ACM-0000'));
    }
}
