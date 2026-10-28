# Stack reference — Laravel (PHP)

Load when `composer.json` exists at the project root (see **Load Mandatory References** in
`../workflow.md`). These checks extend **Analyze → Pass 4**; they apply only to `+` lines and
never replace the neutral checklist. Skip any item whose package the project does not use
(no `livewire/livewire` in `composer.json` → skip the Livewire block).

## Security

- **Raw SQL with interpolation** — `DB::raw`, `whereRaw`, `selectRaw`, `orderByRaw`, `DB::statement` built from request input instead of bindings (`?` / named bindings).
- **Mass assignment** — `Model::create($request->all())` / `->fill($request->all())`, or a model with `$guarded = []`; prefer `$request->validated()` and an explicit `$fillable`.
- **Authorization** — a controller action, route or Livewire action that reads or writes a model without a policy check (`$this->authorize()`, `Gate::allows`, `can` middleware) when the rest of the module uses one.
- **Validation** — input used before a `FormRequest` or `$request->validate()` ran on it.
- **Exposure** — models returned straight from a controller without `$hidden` / an API Resource, leaking columns.

## Performance (Eloquent)

- **N+1** — a relation accessed inside a loop or a Blade `@foreach` without `with()` / `load()` on the query that produced the collection.
- **Unbounded queries** — `->get()` / `->all()` on a table that grows, where `paginate()`, `chunk()` or `cursor()` fits.
- **Queries in accessors** — an accessor or `$appends` attribute that runs a query per model.

## Livewire

- **Public properties are client-writable** — an id or a privileged flag in a public property without `#[Locked]` (v3) or a server-side re-check.
- **Actions trust their arguments** — a `wire:click="delete({{ $id }})"` handler that does not authorize the target.

## Framework hygiene

- `env()` called outside `config/` (returns null once the config is cached).
- A migration that drops or renames a column without a `down()` path, or adds a foreign key without an index the queries need.
- A queued job or event that serializes a model whose state may change before it runs (`SerializesModels` re-fetches; a stale array copy does not).
