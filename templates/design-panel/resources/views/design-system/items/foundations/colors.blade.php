@php
    $groups = [
        'Surfaces' => [
            ['name' => 'Background', 'token' => 'background', 'hex' => '#FFFFFF', 'figma' => 'var(--background)'],
            ['name' => 'Card', 'token' => 'card', 'hex' => '#FFFFFF', 'figma' => 'var(--card)'],
            ['name' => 'Secondary', 'token' => 'secondary', 'hex' => '#F5F5F5', 'figma' => 'var(--secondary)'],
        ],
        'Content' => [
            ['name' => 'Foreground', 'token' => 'foreground', 'hex' => '#09090B', 'figma' => 'var(--foreground)'],
            ['name' => 'Muted Foreground', 'token' => 'muted-foreground', 'hex' => '#71717A', 'figma' => 'var(--muted-foreground)'],
            ['name' => 'Secondary Foreground', 'token' => 'secondary-foreground', 'hex' => '#171717', 'figma' => 'var(--secondary-foreground)'],
            ['name' => 'Popover Foreground', 'token' => 'popover-foreground', 'hex' => '#09090B', 'figma' => 'popover-foreground'],
        ],
        'Action' => [
            ['name' => 'Primary', 'token' => 'primary', 'hex' => '#171717', 'figma' => 'var(--primary)'],
            ['name' => 'Primary Foreground', 'token' => 'primary-foreground', 'hex' => '#FAFAFA', 'figma' => 'var(--primary-foreground)'],
        ],
        'Lines & inputs' => [
            ['name' => 'Border', 'token' => 'border', 'hex' => '#E4E4E7', 'figma' => 'var(--border)'],
            ['name' => 'Input', 'token' => 'input', 'hex' => '#E6E6E6', 'figma' => 'var(--input)'],
            ['name' => 'Sidebar Border', 'token' => 'sidebar-border', 'hex' => '#E6E6E6', 'figma' => 'sidebar/border'],
            ['name' => 'Input Background', 'token' => 'bg-input-30', 'hex' => '#FFFFFF', 'figma' => 'custom/bg-input-30'],
        ],
        'Named' => [
            ['name' => 'White 2', 'token' => 'white-2', 'hex' => '#FFFFFF', 'figma' => 'colors/white 2'],
            ['name' => 'Black 2', 'token' => 'black-2', 'hex' => '#000000', 'figma' => 'colors/black 2'],
        ],
    ];
@endphp

<section class="space-y-10">
    <header class="space-y-1">
        <h2 class="text-3xl font-medium tracking-tight">Colors</h2>
        <p class="text-base text-muted-foreground">
            Semantic tokens pulled from the Figma kit. Every value is a CSS variable declared in
            <code>resources/css/app.css</code> and consumed as a Tailwind utility
            (<code>bg-primary</code>, <code>text-muted-foreground</code>, <code>border-border</code>).
        </p>
    </header>

    <div class="space-y-4">
        <div class="rounded-lg border border-border bg-secondary px-5 py-4 text-sm">
            <p class="font-medium text-foreground">Heads up — the palette mixes two Tailwind scales.</p>
            <p class="text-muted-foreground">
                <code>foreground</code>, <code>muted-foreground</code> and <code>border</code> come from
                <strong>zinc</strong>; <code>primary</code> and <code>secondary</code> from
                <strong>neutral</strong>. <code>input</code> (#E6E6E6) belongs to neither. Faithful to the
                Figma kit as it stands — flagged with design.
            </p>
        </div>

        <div class="rounded-lg border border-border bg-secondary px-5 py-4 text-sm">
            <p class="font-medium text-foreground">This list is exactly what Figma declares — no more.</p>
            <p class="text-muted-foreground">
                The kit has no <code>--muted</code>, <code>--popover</code>, <code>--card-foreground</code>
                or <code>--ring</code>, so neither do we, even though stock shadcn ships them. A component
                that needs one gets it added to Figma first.
            </p>
        </div>
    </div>

    @foreach ($groups as $groupName => $swatches)
        <div class="space-y-4">
            <h3 class="text-base font-medium">{{ $groupName }}</h3>
            <div class="grid grid-cols-2 gap-5 sm:grid-cols-3">
                @foreach ($swatches as $swatch)
                    <div class="space-y-2">
                        <div class="h-28 rounded-lg border border-border" style="background-color: var(--color-{{ $swatch['token'] }})"></div>
                        <div class="space-y-0.5">
                            <p class="text-sm font-medium">{{ $swatch['name'] }}</p>
                            <p class="text-sm text-muted-foreground">{{ $swatch['hex'] }}</p>
                            <p class="text-sm text-muted-foreground">--color-{{ $swatch['token'] }}</p>
                            <p class="text-xs text-muted-foreground">Figma: <code>{{ $swatch['figma'] }}</code></p>
                        </div>
                    </div>
                @endforeach
            </div>
        </div>
    @endforeach
</section>
