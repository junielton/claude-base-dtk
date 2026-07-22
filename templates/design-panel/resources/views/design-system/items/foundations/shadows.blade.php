@php
    $shadows = [
        ['class' => 'shadow-2xs', 'value' => '0 1px 2px 0', 'usage' => 'Buttons, inputs — the kit\'s default elevation'],
        ['class' => 'shadow-xs', 'value' => '0 1px 2px 0', 'usage' => 'Same geometry as 2xs in this kit'],
        ['class' => 'shadow-md', 'value' => '0 4px 6px -1px, 0 2px 4px -2px', 'usage' => 'Dropdowns, popovers'],
        ['class' => 'shadow-lg', 'value' => '0 10px 15px -3px, 0 4px 6px -4px', 'usage' => 'Modals, overlays'],
    ];
@endphp

<section class="space-y-10">
    <header class="space-y-1">
        <h2 class="text-3xl font-medium tracking-tight">Shadows</h2>
        <p class="text-base text-muted-foreground">
            Four levels, all on the same tint: <code>#1A1A1A0D</code> — a near-black at 5% opacity.
        </p>
    </header>

    <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
        @foreach ($shadows as $shadow)
            <div class="space-y-3">
                <div class="flex h-28 items-center justify-center rounded-lg border border-border bg-background {{ $shadow['class'] }}">
                    <span class="text-sm font-medium">{{ $shadow['class'] }}</span>
                </div>
                <div class="space-y-0.5">
                    <p class="text-sm text-muted-foreground">{{ $shadow['value'] }}</p>
                    <p class="text-sm text-muted-foreground">{{ $shadow['usage'] }}</p>
                </div>
            </div>
        @endforeach
    </div>

    <p class="text-sm text-muted-foreground">
        <code>2xs</code> and <code>xs</code> are identical in the Figma kit. Both are kept so component
        code can mirror the layer name it was built from.
    </p>
</section>
