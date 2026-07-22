@php
    // Display sizes carry tracking-tight (-0.025em); body sizes carry none.
    $display = [
        ['class' => 'text-6xl', 'spec' => '60 / 1', 'weight' => 'font-medium'],
        ['class' => 'text-5xl', 'spec' => '48 / 1', 'weight' => 'font-medium'],
        ['class' => 'text-4xl', 'spec' => '36 / 40', 'weight' => 'font-medium'],
        ['class' => 'text-3xl', 'spec' => '30 / 36 · also 30 / 1', 'weight' => 'font-medium'],
        ['class' => 'text-2xl', 'spec' => '24 / 32', 'weight' => 'font-medium'],
    ];

    $body = [
        ['class' => 'text-lg', 'spec' => '18 / 28'],
        ['class' => 'text-base', 'spec' => '16 / 24'],
        ['class' => 'text-sm', 'spec' => '14 / 20'],
        ['class' => 'text-xs', 'spec' => '12 / 16 · +1% at regular'],
    ];

    $weights = [
        ['class' => 'font-normal', 'label' => 'Regular', 'value' => 400],
        ['class' => 'font-medium', 'label' => 'Medium', 'value' => 500],
        ['class' => 'font-semibold', 'label' => 'SemiBold', 'value' => 600],
    ];
@endphp

<section class="space-y-10">
    <header class="space-y-1">
        <h2 class="text-3xl font-medium tracking-tight">Typography</h2>
        <p class="text-base text-muted-foreground">
            The scale matches Tailwind's defaults exactly — nothing is redeclared
            in <code>@theme</code> beyond the font family.
        </p>
    </header>

    <div class="space-y-4">
        <h3 class="text-base font-medium">Display <span class="font-normal text-muted-foreground">— always with <code>tracking-tight</code></span></h3>
        <div class="divide-y divide-border rounded-lg border border-border">
            @foreach ($display as $row)
                <div class="flex items-baseline justify-between gap-6 px-5 py-4">
                    <p class="{{ $row['class'] }} {{ $row['weight'] }} truncate tracking-tight">Cooling Towers</p>
                    <div class="shrink-0 text-right">
                        <p class="text-sm font-medium">{{ $row['class'] }}</p>
                        <p class="text-sm text-muted-foreground">{{ $row['spec'] }}</p>
                    </div>
                </div>
            @endforeach
        </div>
    </div>

    <div class="space-y-4">
        <h3 class="text-base font-medium">Body <span class="font-normal text-muted-foreground">— no tracking adjustment</span></h3>
        <div class="divide-y divide-border rounded-lg border border-border">
            @foreach ($body as $row)
                <div class="flex items-baseline justify-between gap-6 px-5 py-4">
                    <p class="{{ $row['class'] }}">Acme Inc. is helping thousands of creators move faster.</p>
                    <div class="shrink-0 text-right">
                        <p class="text-sm font-medium">{{ $row['class'] }}</p>
                        <p class="text-sm text-muted-foreground">{{ $row['spec'] }}</p>
                    </div>
                </div>
            @endforeach
        </div>
    </div>

    <div class="space-y-4">
        <h3 class="text-base font-medium">Weights</h3>
        <div class="divide-y divide-border rounded-lg border border-border">
            @foreach ($weights as $weight)
                <div class="flex items-baseline justify-between gap-6 px-5 py-4">
                    <p class="text-lg {{ $weight['class'] }}">The quick brown fox</p>
                    <div class="shrink-0 text-right">
                        <p class="text-sm font-medium">{{ $weight['class'] }}</p>
                        <p class="text-sm text-muted-foreground">{{ $weight['value'] }}</p>
                    </div>
                </div>
            @endforeach
        </div>
        <p class="text-sm text-muted-foreground">
            The spec column above lists the exact size and line-height available for each weight.
        </p>
    </div>
</section>
