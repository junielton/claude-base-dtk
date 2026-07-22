<x-design-system.shell :title="'Design System · ' . $item['label']" :scripts="$item['scripts'] ?? false" class="min-h-screen">

    <header class="sticky top-0 z-10 border-b border-border bg-background">
        <div class="flex h-16 items-center gap-6 px-6">
            <a href="{{ route('design-system') }}"
                class="whitespace-nowrap rounded-md text-base font-medium outline-none focus-visible:ring-2 focus-visible:ring-foreground">
                {{ config('app.name') }} <span class="text-muted-foreground">/ Design System</span>
            </a>
            <nav class="flex items-center gap-1 overflow-x-auto" aria-label="Design system areas">
                @foreach ($areas as $key => $area)
                    <x-ui.panel-nav-link variant="topbar" :href="route('design-system', $key)" :active="$key === $areaKey">
                        {{ $area['label'] }}
                    </x-ui.panel-nav-link>
                @endforeach
            </nav>
        </div>
    </header>

    <div class="flex">
        <aside class="min-h-[calc(100vh-4rem)] w-56 shrink-0 border-r border-border p-4">
            <p class="px-3 pb-2 text-sm uppercase tracking-widest text-muted-foreground">
                {{ $areas[$areaKey]['label'] }}
            </p>
            <nav class="flex flex-col gap-0.5" aria-label="{{ $areas[$areaKey]['label'] }} items">
                @foreach ($areas[$areaKey]['items'] as $key => $entry)
                    <x-ui.panel-nav-link variant="sidebar" :href="route('design-system', [$areaKey, $key])" :active="$key === $itemKey">
                        {{ $entry['label'] }}
                    </x-ui.panel-nav-link>
                @endforeach
            </nav>
        </aside>

        <main class="max-w-4xl flex-1 px-10 py-12">
            @include($item['view'], [
                'itemLabel' => $item['label'],
                'itemKey' => $itemKey,
                'areaKey' => $areaKey,
                'item' => $item,
            ])
        </main>
    </div>
</x-design-system.shell>
