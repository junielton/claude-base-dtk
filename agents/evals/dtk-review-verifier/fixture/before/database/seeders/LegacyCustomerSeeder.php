<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;

/**
 * One-off import of pre-2019 customers from the old billing system. Writes
 * straight to the table because the source export has no email column for
 * most of these accounts — this bypasses App\Observers\CustomerObserver
 * entirely, since that only fires on Eloquent saves.
 */
class LegacyCustomerSeeder extends Seeder
{
    public function run(): void
    {
        DB::table('customers')->insert([
            'name' => 'Acme Distribuidora Ltda',
            'contact_email' => null,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }
}
