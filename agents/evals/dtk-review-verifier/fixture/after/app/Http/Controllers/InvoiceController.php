<?php

namespace App\Http\Controllers;

use App\Models\Invoice;
use Illuminate\Http\Request;

class InvoiceController extends Controller
{
    public function show(Invoice $invoice)
    {
        $cents = $invoice->total_cents;
        $prefix = $cents < 0 ? '-R$ ' : 'R$ ';
        $total = $prefix . number_format(abs($cents) / 100, 2, ',', '.');

        return response()->json([
            'total' => $total,
            'customer' => $invoice->customer->name,
        ]);
    }

    public function receipt(Invoice $invoice)
    {
        $email = $invoice->customer->contact_email;

        return response()->json([
            'sent_to' => strtolower($email),
        ]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'total_cents' => ['required', 'integer', 'min:1'],
            'customer_id' => ['required', 'exists:customers,id'],
        ]);

        return response()->json(Invoice::create($data));
    }
}
