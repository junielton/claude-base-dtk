<?php

namespace Tests\Feature\DesignSystem;

use Tests\TestCase;

class PanelTest extends TestCase
{
    public function test_panel_renders_the_first_area_and_item(): void
    {
        config(['design-system.enabled' => true]);

        $this->withoutVite()->get('/design-system')->assertOk()->assertSee('Foundations');
    }

    public function test_unknown_area_404s(): void
    {
        config(['design-system.enabled' => true]);

        $this->withoutVite()->get('/design-system/nope')->assertNotFound();
    }

    public function test_preview_404s_without_a_preview_key(): void
    {
        config(['design-system.enabled' => true]);

        $this->withoutVite()->get('/design-system/preview/foundations/colors')->assertNotFound();
    }

    public function test_panel_is_hidden_when_disabled(): void
    {
        config(['design-system.enabled' => false]);

        $this->withoutVite()->get('/design-system')->assertNotFound();
    }
}
