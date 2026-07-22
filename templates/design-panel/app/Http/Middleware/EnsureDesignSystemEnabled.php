<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureDesignSystemEnabled
{
    /**
     * Abort with 404 when the design system panel is switched off, so its
     * routes never surface in an environment that did not opt in.
     *
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        abort_unless(config('design-system.enabled'), 404);

        return $next($request);
    }
}
