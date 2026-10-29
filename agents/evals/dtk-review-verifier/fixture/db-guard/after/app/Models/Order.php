<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Order extends Model
{
    protected $fillable = ['reference', 'customer_id', 'total_cents', 'status'];

    public static function findByReference(string $reference): ?self
    {
        return static::where('reference', trim($reference))->first();
    }
}
