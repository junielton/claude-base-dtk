<a
    href="{{ $href }}"
    {{ $attributes->class($variant->classes($active)) }}
    @if ($active) aria-current="page" @endif
>{{ $slot }}</a>
