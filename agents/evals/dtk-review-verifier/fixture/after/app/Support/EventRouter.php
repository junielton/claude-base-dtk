<?php

namespace App\Support;

/**
 * Fires domain events by name. The concrete event class is built from a string
 * at runtime, so no static analysis can enumerate which events flow through here.
 */
class EventRouter
{
    public function fire(string $name, array $payload): void
    {
        $class = 'App\\Events\\' . $name;

        event(new $class(...$payload));
    }
}
