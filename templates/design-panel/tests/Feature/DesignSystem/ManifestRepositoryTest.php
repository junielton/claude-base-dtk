<?php

namespace Tests\Feature\DesignSystem;

use App\Support\DesignSystem\ManifestRepository;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class ManifestRepositoryTest extends TestCase
{
    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = 'design/manifests-test-'.uniqid();
        config(['design-system.manifests' => $this->dir]);
        File::makeDirectory(base_path($this->dir), recursive: true);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory(base_path($this->dir));
        parent::tearDown();
    }

    public function test_finds_a_manifest_by_registry_entry(): void
    {
        File::put(base_path($this->dir.'/button.json'), json_encode([
            'component' => 'ui.button',
            'registry' => ['area' => 'components', 'item' => 'button'],
            'figma' => ['fileKey' => 'abc', 'desktop' => ['nodeId' => '1:2']],
        ]));

        $found = app(ManifestRepository::class)->find('components', 'button');

        $this->assertSame('ui.button', $found['component']);
        $this->assertNull(app(ManifestRepository::class)->find('components', 'ghost'));
    }

    public function test_malformed_manifest_is_skipped_not_fatal(): void
    {
        File::put(base_path($this->dir.'/broken.json'), '{not json');

        $this->assertSame([], app(ManifestRepository::class)->all());
    }
}
