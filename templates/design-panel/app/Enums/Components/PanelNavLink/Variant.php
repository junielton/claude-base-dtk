<?php

namespace App\Enums\Components\PanelNavLink;

enum Variant: string
{
    case Topbar = 'topbar';
    case Sidebar = 'sidebar';

    /**
     * Tailwind classes for the link in the given active state.
     */
    public function classes(bool $active): string
    {
        $base = 'rounded-md text-sm outline-none transition-colors focus-visible:ring-2 focus-visible:ring-foreground';
        $inactive = 'text-muted-foreground hover:bg-secondary hover:text-foreground focus-visible:bg-secondary focus-visible:text-foreground';

        return match ($this) {
            self::Topbar => "{$base} px-3 py-1.5 font-medium ".($active ? 'bg-primary text-primary-foreground' : $inactive),
            self::Sidebar => "{$base} px-3 py-2 ".($active ? 'bg-secondary font-medium text-foreground' : $inactive),
        };
    }
}
