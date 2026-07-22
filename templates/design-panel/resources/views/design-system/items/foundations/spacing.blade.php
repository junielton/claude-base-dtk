@php
    // The kit uses the stock 4px scale; these are the steps it actually reaches for.
    $steps = [
        ['step' => '0.5', 'px' => 2],
        ['step' => '1', 'px' => 4],
        ['step' => '1.5', 'px' => 6],
        ['step' => '2', 'px' => 8],
        ['step' => '2.5', 'px' => 10],
        ['step' => '3', 'px' => 12],
        ['step' => '3.5', 'px' => 14],
        ['step' => '4', 'px' => 16],
        ['step' => '5', 'px' => 20],
        ['step' => '6', 'px' => 24],
        ['step' => '8', 'px' => 32],
        ['step' => '10', 'px' => 40],
        ['step' => '12', 'px' => 48],
    ];

    $grid = [
        ['token' => 'section', 'px' => 80, 'usage' => 'Vertical padding on every marketing section'],
        ['token' => 'container-gap', 'px' => 64, 'usage' => 'Gap between blocks inside a container'],
        ['token' => 'gutter', 'px' => 36, 'usage' => 'Column gap — not a stock Tailwind step'],
        ['token' => 'container-x', 'px' => 32, 'usage' => 'Horizontal container padding'],
    ];
@endphp

<section class="space-y-10">
    <header class="space-y-1">
        <h2 class="text-3xl font-medium tracking-tight">Spacing</h2>
        <p class="text-base text-muted-foreground">
            A stock 4px scale — Tailwind's default, unmodified. On top of it sit four named tokens for
            the marketing grid measured off the 1440px artboard.
        </p>
    </header>

    <div class="space-y-4">
        <h3 class="text-base font-medium">Scale</h3>
        <div class="divide-y divide-border rounded-lg border border-border">
            @foreach ($steps as $item)
                <div class="flex items-center gap-6 px-5 py-3">
                    <p class="w-16 shrink-0 text-sm font-medium tabular-nums">{{ $item['step'] }}</p>
                    <p class="w-16 shrink-0 text-sm tabular-nums text-muted-foreground">{{ $item['px'] }}px</p>
                    <div class="h-4 rounded-sm bg-primary" style="width: {{ $item['px'] }}px"></div>
                </div>
            @endforeach
        </div>
    </div>

    <div class="space-y-4">
        <h3 class="text-base font-medium">Marketing grid</h3>
        <div class="divide-y divide-border rounded-lg border border-border">
            @foreach ($grid as $item)
                <div class="space-y-2 px-5 py-4">
                    <div class="flex items-baseline justify-between gap-6">
                        <p class="text-sm font-medium">--spacing-{{ $item['token'] }}</p>
                        <p class="shrink-0 text-sm tabular-nums text-muted-foreground">{{ $item['px'] }}px</p>
                    </div>
                    <div class="h-3 rounded-sm bg-primary" style="width: {{ $item['px'] }}px"></div>
                    <p class="text-sm text-muted-foreground">{{ $item['usage'] }}</p>
                </div>
            @endforeach
        </div>
        <p class="text-sm text-muted-foreground">
            Used as <code>py-section</code>, <code>gap-gutter</code>, <code>px-container-x</code>.
            Container width is <code>max-w-7xl</code> (1280px), also stock.
        </p>
    </div>
</section>
