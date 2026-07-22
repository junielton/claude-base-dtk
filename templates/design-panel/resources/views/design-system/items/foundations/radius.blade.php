@php
    $radii = [
        ['class' => 'rounded-sm', 'token' => '--radius-sm', 'calc' => 'calc(--radius - 4px)', 'px' => 8],
        ['class' => 'rounded-md', 'token' => '--radius-md', 'calc' => 'calc(--radius - 2px)', 'px' => 10],
        ['class' => 'rounded-lg', 'token' => '--radius-lg', 'calc' => '--radius', 'px' => 12],
        ['class' => 'rounded-full', 'token' => 'radius/rounded-full', 'calc' => '9999px', 'px' => 9999],
    ];
@endphp

<section class="space-y-10">
    <header class="space-y-1">
        <h2 class="text-3xl font-medium tracking-tight">Radius</h2>
        <p class="text-base text-muted-foreground">
            One root value, two derived — the kit only ever computes <code>-2px</code> and
            <code>-4px</code>, so there is no <code>xl</code> step. Buttons use
            <code>rounded-md</code> (10px); cards and images use <code>rounded-lg</code> (12px).
        </p>
    </header>

    <div class="rounded-lg border border-border bg-secondary px-5 py-4 text-sm">
        <p class="font-medium text-foreground">The Figma kit contradicts itself here.</p>
        <p class="text-muted-foreground">
            Its variable reads <code>--radius: 14</code>, but its own derived values
            (<code>calc(--radius - 2px) = 10</code>, <code>- 4px = 8</code>) only hold if the root is 12.
            We use <strong>12px</strong>, because that is what reproduces the rendered design — a button
            in the kit measures 10px. Flagged with design; revisit if the kit is corrected.
        </p>
    </div>

    <div class="grid grid-cols-2 gap-5 sm:grid-cols-3">
        @foreach ($radii as $radius)
            <div class="space-y-2">
                <div class="flex h-28 items-center justify-center border border-border bg-secondary {{ $radius['class'] }}">
                    <span class="text-sm text-muted-foreground">{{ $radius['px'] === 9999 ? '∞' : $radius['px'] . 'px' }}</span>
                </div>
                <div class="space-y-0.5">
                    <p class="text-sm font-medium">{{ $radius['class'] }}</p>
                    <p class="text-sm text-muted-foreground">{{ $radius['token'] }}</p>
                    <p class="text-sm text-muted-foreground">{{ $radius['calc'] }}</p>
                </div>
            </div>
        @endforeach
    </div>
</section>
