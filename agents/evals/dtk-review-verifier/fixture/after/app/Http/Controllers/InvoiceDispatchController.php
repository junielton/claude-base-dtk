<?php

namespace App\Http\Controllers;

use App\Contracts\InvoiceNotifier;
use App\Models\Invoice;

class InvoiceDispatchController extends Controller
{
    public function __construct(private InvoiceNotifier $notifier)
    {
    }

    public function send(Invoice $invoice)
    {
        $this->notifier->notify($invoice);

        return response()->json(['ok' => true]);
    }
}
