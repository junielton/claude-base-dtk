<?php

namespace App\Http\Controllers\DesignSystem;

use App\Http\Controllers\Controller;
use Illuminate\View\View;

class PanelController extends Controller
{
    /**
     * Render the design system panel for the selected area and item.
     * Falls back to the first area/item; unknown keys 404 so broken
     * deep-links surface instead of silently redirecting.
     */
    public function __invoke(?string $area = null, ?string $item = null): View
    {
        /** @var array<string, array{label: string, items: array<string, array{label: string, view: string, preview?: string, scripts?: bool}>}> $areas */
        $areas = config('design-system.areas');

        $areaKey = $area ?? array_key_first($areas);
        abort_unless(isset($areas[$areaKey]), 404);

        $items = $areas[$areaKey]['items'];
        $itemKey = $item ?? array_key_first($items);
        abort_unless(isset($items[$itemKey]), 404);

        return view('design-system.layout', [
            'areas' => $areas,
            'areaKey' => $areaKey,
            'itemKey' => $itemKey,
            'item' => $items[$itemKey],
        ]);
    }
}
