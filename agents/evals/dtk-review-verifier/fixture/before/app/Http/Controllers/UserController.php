<?php

namespace App\Http\Controllers;

use App\Models\User;

class UserController extends Controller
{
    public function show(User $user)
    {
        return response()->json([
            'id' => $user->id,
            'name' => $user->name,
        ]);
    }
}
