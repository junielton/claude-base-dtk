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
            One root value, two derived — this scale only computes <code>-2px</code> and
            <code>-4px</code> from the root, so there is no <code>xl</code> step.
        </p>
    </header>

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
