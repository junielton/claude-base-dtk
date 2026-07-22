@use('App\Support\DesignSystem\ManifestRepository')

@php
    $manifest = app(ManifestRepository::class)->find($areaKey, $itemKey);
    $sync = $manifest['sync'] ?? null;
    $badge = match ($sync['lastResult'] ?? 'never-checked') {
        'in-sync' => ['label' => 'In sync', 'classes' => 'bg-green-100 text-green-800'],
        'drifted' => ['label' => 'Figma drifted', 'classes' => 'bg-amber-100 text-amber-800'],
        'unreachable' => ['label' => 'Node unreachable', 'classes' => 'bg-red-100 text-red-800'],
        default => ['label' => 'Never checked', 'classes' => 'bg-secondary text-muted-foreground'],
    };
@endphp

<section class="space-y-8">
    <header class="space-y-2">
        <div class="flex items-center gap-3">
            <h2 class="text-3xl font-medium tracking-tight">{{ $itemLabel }}</h2>
            <span class="rounded-full px-2.5 py-0.5 text-xs font-medium {{ $badge['classes'] }}"
                @if ($sync['lastCheckedAt'] ?? false) title="Last checked {{ $sync['lastCheckedAt'] }}" @endif
            >{{ $badge['label'] }}</span>
        </div>
        @if ($manifest && ($manifest['figma']['desktop']['url'] ?? false))
            <a href="{{ $manifest['figma']['desktop']['url'] }}" target="_blank" rel="noopener"
                class="inline-flex items-center gap-1 text-sm text-muted-foreground underline-offset-4 hover:underline focus-visible:ring-2 focus-visible:ring-foreground">
                Open in Figma ↗
            </a>
        @endif
    </header>

    @isset($item['preview'])
        <div class="rounded-lg border border-border p-8">
            <x-dynamic-component :component="$item['preview']"
                :attributes="new Illuminate\View\ComponentAttributeBag($item['previewProps'] ?? [])" />
        </div>
    @endisset

    @if ($manifest && ! empty($manifest['api']['props']))
        <div class="space-y-3">
            <h3 class="text-lg font-medium">API</h3>
            <table class="w-full text-left text-sm">
                <thead class="text-muted-foreground">
                    <tr><th class="py-1.5 pr-6 font-medium">Prop</th><th class="py-1.5 font-medium">Type</th></tr>
                </thead>
                <tbody>
                    @foreach ($manifest['api']['props'] as $prop)
                        <tr class="border-t border-border">
                            <td class="py-1.5 pr-6 font-mono">{{ $prop['name'] }}</td>
                            <td class="py-1.5 font-mono text-muted-foreground">{{ $prop['type'] }}</td>
                        </tr>
                    @endforeach
                    @if ($manifest['api']['variants']['cases'] ?? false)
                        <tr class="border-t border-border">
                            <td class="py-1.5 pr-6 font-mono">variant</td>
                            <td class="py-1.5 font-mono text-muted-foreground">{{ implode(' | ', $manifest['api']['variants']['cases']) }}</td>
                        </tr>
                    @endif
                </tbody>
            </table>
        </div>
    @endif

    @isset($item['showcase'])
        @include($item['showcase'], ['itemLabel' => $itemLabel, 'itemKey' => $itemKey, 'areaKey' => $areaKey])
    @endisset
</section>
