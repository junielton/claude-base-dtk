<?php

namespace App\View\Components\Ui;

use App\Enums\Components\PanelNavLink\Variant;
use Illuminate\View\Component;
use Illuminate\View\View;

class PanelNavLink extends Component
{
    public Variant $variant;

    public function __construct(
        Variant|string $variant,
        public string $href,
        public bool $active = false,
    ) {
        $this->variant = is_string($variant) ? Variant::from($variant) : $variant;
    }

    public function render(): View
    {
        return view('components.ui.panel-nav-link');
    }
}
