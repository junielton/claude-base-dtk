<?php

namespace App\Observers;

use App\Models\Customer;

/**
 * Defensive normalization for records created through the app: a customer
 * saved via Eloquent never persists a null contact_email. This does NOT cover
 * rows written outside Eloquent — see database/seeders/LegacyCustomerSeeder.
 */
class CustomerObserver
{
    public function saving(Customer $customer): void
    {
        $customer->contact_email = $customer->contact_email ?? '';
    }
}
