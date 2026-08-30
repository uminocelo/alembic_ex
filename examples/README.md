# Alembic examples

Runnable scripts demonstrating how to use Alembic. Each one is a plain
`.exs` script — run it from the project root with `mix run`:

```bash
mix run examples/01_hello_world.exs
mix run examples/02_control_flow.exs
mix run examples/03_filters.exs
mix run examples/04_custom_filter.exs
mix run examples/05_inheritance/run.exs
mix run examples/06_includes/run.exs
mix run examples/07_render_file/run.exs
mix run examples/08_error_handling.exs
```

| Script | What it shows |
|---|---|
| [`01_hello_world.exs`](01_hello_world.exs) | `render_string/3`, `compile/2` + `render/3`, bang variants |
| [`02_control_flow.exs`](02_control_flow.exs) | `{% if %}`/`{% elsif %}`/`{% else %}`, Liquid truthiness, `{% for %}` with `forloop`, `{% assign %}` |
| [`03_filters.exs`](03_filters.exs) | Built-in filters, chaining |
| [`04_custom_filter.exs`](04_custom_filter.exs) | Implementing `Alembic.Filter`, registering it globally via config, and per call via the `custom_filters:` option |
| [`05_inheritance/`](05_inheritance/) | `{% extends %}` / `{% block %}`, `{{ block.super }}`, real files on disk |
| [`06_includes/`](06_includes/) | `{% include %}` with `with`, and implicit scope sharing |
| [`07_render_file/`](07_render_file/) | `render_file/3`, the compiled-AST cache, `cache: false` |
| [`08_error_handling.exs`](08_error_handling.exs) | `{:error, {stage, reason}}` shapes, `strict: true`, bang-variant exceptions |

You'll see a one-line warning at startup:

```
[warning] Alembic: :template_roots is not configured — render_file/3 will never find a template. ...
```

That's `Alembic.Config.validate!/0` running at application boot — harmless
here since every example passes `roots:` explicitly per call instead of
relying on global config (`config :alembic, template_roots: [...]`).

## Where to go next

- [`../README.md`](../README.md) — installation, configuration reference,
  Grimoire integration
- [`../docs/grammar.md`](../docs/grammar.md) — the formal template grammar
- [`../COMPATIBILITY.md`](../COMPATIBILITY.md) — what's supported vs. how
  this deviates from upstream Liquid
- `mix docs` — full API reference for every module (`Alembic`,
  `Alembic.Filters`, `Alembic.Context`, etc.)
