@use('Illuminate\View\ComponentAttributeBag')

<x-design-system.shell :title="'Preview · ' . $label" :scripts="$scripts ?? false">
    <x-dynamic-component :component="$previewComponent" :attributes="new ComponentAttributeBag($props ?? [])" />
</x-design-system.shell>
