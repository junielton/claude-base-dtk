<?php

namespace App\Support\DesignSystem;

use Illuminate\Support\Facades\Log;

class ManifestRepository
{
    /**
     * Find the manifest for a registry entry, or null when the component has
     * none yet. A malformed manifest is skipped (and logged) — it must never
     * break the panel.
     *
     * @return array<string, mixed>|null
     */
    public function find(string $area, string $item): ?array
    {
        foreach ($this->all() as $manifest) {
            if (($manifest['registry']['area'] ?? null) === $area
                && ($manifest['registry']['item'] ?? null) === $item) {
                return $manifest;
            }
        }

        return null;
    }

    /**
     * @return list<array<string, mixed>>
     */
    public function all(): array
    {
        $dir = base_path(config('design-system.manifests'));
        $manifests = [];

        foreach (glob($dir.'/*.json') ?: [] as $path) {
            if (str_ends_with($path, '.schema.json')) {
                continue;
            }
            $manifest = $this->read($path);
            if ($manifest !== null) {
                $manifests[] = $manifest;
            }
        }

        return $manifests;
    }

    /**
     * @return array<string, mixed>|null
     */
    private function read(string $path): ?array
    {
        $data = json_decode((string) file_get_contents($path), true);

        if (! is_array($data)
            || ! is_string($data['component'] ?? null)
            || ! is_array($data['registry'] ?? null)
            || ! is_string($data['figma']['fileKey'] ?? null)) {
            Log::warning("design-system: ignoring malformed manifest at {$path}");

            return null;
        }

        return $data;
    }
}
