<?php

namespace App\Contracts;

use App\Models\Invoice;

interface InvoiceNotifier
{
    public function notify(Invoice $invoice): void;
}
