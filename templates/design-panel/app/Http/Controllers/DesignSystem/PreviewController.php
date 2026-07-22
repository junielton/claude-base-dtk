<?php

namespace App\Http\Controllers\DesignSystem;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\View\View;

class PreviewController extends Controller
{
    /**
     * Render a single registered component standalone and full-bleed, so the
     * panel can embed it in an iframe and resize it to any viewport width.
     * Only items that declare a `preview` component name are previewable;
     * everything else 404s.
     */
    public function __invoke(Request $request, string $area, string $item): View
    {
        /** @var array<string, array{label: string, items: array<string, array{label: string, view: string, preview?: string, scripts?: bool, previewProps?: array<string, mixed>}>}> $areas */
        $areas = config('design-system.areas');

        $entry = $areas[$area]['items'][$item] ?? null;
        abort_unless($entry !== null && isset($entry['preview']), 404);

        $variant = $request->query('variant');
        $props = $entry['previewProps'] ?? [];
        if ($variant !== null) {
            $props['variant'] = $variant;
        }

        return view('design-system.preview', [
            'previewComponent' => $entry['preview'],
            'label' => $entry['label'],
            'props' => $props,
            'scripts' => $entry['scripts'] ?? false,
        ]);
    }
}
