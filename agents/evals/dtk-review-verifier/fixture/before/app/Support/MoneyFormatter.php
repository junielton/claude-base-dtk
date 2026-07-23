<?php

namespace App\Support;

class MoneyFormatter
{
    public static function toBrl(int $cents): string
    {
        return 'R$ ' . number_format($cents / 100, 2, ',', '.');
    }
}
