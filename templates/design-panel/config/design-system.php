<?php

return [
    /*
     * Gates the whole panel. A config flag rather than an isProduction()
     * check because staging environments often run APP_ENV=production and
     * are exactly where the team needs the panel.
     */
    'enabled' => (bool) env('DESIGN_SYSTEM_ENABLED', env('APP_ENV') !== 'production'),

    /*
     * Where component manifests live, relative to base_path(). Written only
     * by dtk's write-manifest.mjs; read by ManifestRepository.
     */
    'manifests' => 'design/manifests',

    /*
     * Drives the panel topbar (areas) and sidebar (items). Adding a
     * component is a registry entry, not a route. Keys per item:
     *   view          Blade view for the showcase page. Components should use
     *                 'design-system.items._component' (manifest-aware default).
     *   showcase      optional extra view @included inside the default page.
     *   preview       <x-dynamic-component> name rendered standalone by the
     *                 preview route (without it, preview 404s).
     *   previewProps  extra props for the preview component.
     *   scripts       true opts the page into the JS bundle.
     */
    'areas' => [
        'foundations' => [
            'label' => 'Foundations',
            'items' => [
                'colors' => ['label' => 'Colors', 'view' => 'design-system.items.foundations.colors'],
                'typography' => ['label' => 'Typography', 'view' => 'design-system.items.foundations.typography'],
                'spacing' => ['label' => 'Spacing', 'view' => 'design-system.items.foundations.spacing'],
                'radius' => ['label' => 'Radius', 'view' => 'design-system.items.foundations.radius'],
                'shadows' => ['label' => 'Shadows', 'view' => 'design-system.items.foundations.shadows'],
            ],
        ],

        'components' => [
            'label' => 'Components',
            'items' => [
                // Populated by dtk:implement-design. Example:
                // 'button' => [
                //     'label' => 'Button',
                //     'view' => 'design-system.items._component',
                //     'preview' => 'ui.button',
                //     'previewProps' => ['label' => 'Get started'],
                // ],
            ],
        ],
    ],

    /*
     * Icon registry: each entry maps to <x-ui.icons.{name}> plus a category
     * for the panel's icon pages. Populated as components need icons.
     */
    'icons' => [],
];
