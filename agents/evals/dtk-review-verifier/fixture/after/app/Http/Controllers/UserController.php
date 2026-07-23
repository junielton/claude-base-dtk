<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class UserController extends Controller
{
    public function show(User $user)
    {
        return response()->json([
            'id' => $user->id,
            'name' => $user->name,
        ]);
    }

    public function search(Request $request)
    {
        $term = $request->query('q');

        $users = DB::select(
            DB::raw("SELECT id, name FROM users WHERE name LIKE '%{$term}%'")
        );

        return response()->json($users);
    }
}
