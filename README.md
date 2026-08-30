# Alembic

[![Hex.pm](https://img.shields.io/hexpm/v/alembic_template_engine.svg)](https://hex.pm/packages/alembic_template_engine)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A Liquid-compatible template engine for Elixir, with **zero runtime
dependencies** — built entirely on Elixir and OTP standard library
functionality.

## Quick start

```elixir
# 1. Add the dependency (the OTP app is :alembic; the Hex package name is
#    alembic_template_engine, so the `hex:` key is required)
def deps do
  [{:alembic, "~> 0.1.0", hex: "alembic_template_engine"}]
end
```

```elixir
# 2. Configure template roots (config/config.exs) — only needed for render_file/3
config :alembic, template_roots: ["priv/templates"]
```

```elixir
# 3. Render
Alembic.render_string("Hello, {{ name }}!", %{"name" => "World"})
#=> {:ok, "Hello, World!"}

Alembic.render_file("index.html", %{"title" => "Home"})
#=> {:ok, "<html>...</html>"}
```

## Features

- **Compile once, render many times** — `compile/2` and `render/3` are
  separate steps, so a caller can parse a template once and reuse the AST.
  See [`Alembic`](https://hexdocs.pm/alembic_template_engine/Alembic.html).
- **Full control flow** — `{% if %}` / `{% elsif %}` / `{% else %}`,
  `{% for %}` with `forloop` metadata, `{% assign %}`, comparison and
  logical operators. See
  [`Alembic.Parser`](https://hexdocs.pm/alembic_template_engine/Alembic.Parser.html)
  and [`docs/grammar.md`](docs/grammar.md).
- **Built-in filter library** — the full Liquid string/array/number/misc
  filter catalog, plus custom filter registration. See
  [`Alembic.Filters`](https://hexdocs.pm/alembic_template_engine/Alembic.Filters.html)
  and [`Alembic.Filter`](https://hexdocs.pm/alembic_template_engine/Alembic.Filter.html).
- **Template inheritance** — multi-level `{% extends %}` / `{% block %}`
  chains with `{{ block.super }}`. See
  [`Alembic.Inheritance`](https://hexdocs.pm/alembic_template_engine/Alembic.Inheritance.html).
- **Partials** — `{% include %}` with optional variable passing.
- **ETS-backed compiled-template cache** — automatic mtime-based
  invalidation, `cache: false` per-call bypass. See
  [`Alembic.Cache`](https://hexdocs.pm/alembic_template_engine/Alembic.Cache.html).
- **Strict mode** — `strict: true` errors on undefined variables instead of
  silently rendering `""`, useful in development.
- **Path-traversal-safe file loading** across multiple template roots. See
  [`Alembic.Loader`](https://hexdocs.pm/alembic_template_engine/Alembic.Loader.html).

See [`COMPATIBILITY.md`](COMPATIBILITY.md) for the full picture of what's
supported, what intentionally deviates from upstream Liquid, and what's out
of scope for this release.

## Configuration

```elixir
# config/config.exs
config :alembic,
  template_roots: ["priv/templates"],
  template_extensions: [".html", ".liquid"],
  cache: true,
  custom_filters: [],
  max_inheritance_depth: 10
```

| Key | Type | Default | Description |
|---|---|---|---|
| `:template_roots` | `[String.t()]` | `[]` | Directories searched, in order, by `render_file/3` |
| `:template_extensions` | `[String.t()]` | `[".html", ".liquid"]` | Extensions tried when a name has none |
| `:cache` | `boolean()` | `true` | Enable/disable the compiled-AST cache |
| `:custom_filters` | `[module()]` | `[]` | Modules implementing `Alembic.Filter` |
| `:max_inheritance_depth` | `pos_integer()` | `10` | Max `{% extends %}` chain length |

Every key has a per-call override too — see the options table in
[`Alembic`'s moduledoc](https://hexdocs.pm/alembic_template_engine/Alembic.html).

### Custom filters

```elixir
defmodule MyApp.Filters.Money do
  @behaviour Alembic.Filter

  @impl true
  def name, do: "money"

  @impl true
  def apply(cents, []) when is_integer(cents) do
    {:ok, "$" <> :erlang.float_to_binary(cents / 100, decimals: 2)}
  end
end
```

```elixir
config :alembic, custom_filters: [MyApp.Filters.Money]
```

```liquid
{{ price_cents | money }}  {# => "$19.99" #}
```

## Dependency policy

Alembic has **zero runtime dependencies**. Development tooling
(`ex_doc`, `credo`, `dialyxir`, `benchee`) is `runtime: false` and never
becomes part of the dependency graph of an application that depends on
Alembic.

## Alembic and Grimoire

Alembic is developed as an independent library, intended as the template
engine powering [Grimoire](https://github.com/uminocelo/grimoire_ex), a
static site generator. During local development, Grimoire can reference
Alembic as a path dependency:

```elixir
defp deps do
  [
    {:alembic, path: "../alembic"}
  ]
end
```

This separation keeps template compilation and rendering independent from
the static site generator's file discovery, content processing, routing,
and output generation:

```
Grimoire
   │
   ├── discovers source files
   ├── loads content and metadata
   ├── selects templates
   │
   └── calls Alembic
          ├── compile/2
          ├── render/3
          └── render_file/3
```

## Development

```bash
mix deps.get              # install dependencies
mix test                  # run the test suite (unit + integration + doctests)
mix test --cover          # with coverage report
mix format --check-formatted
mix credo --strict        # static analysis
mix dialyzer              # type checking
mix docs                  # generate documentation
mix run bench/*.exs       # run a benchmark script (see BENCHMARKS.md)
mix hex.build              # build the Hex package locally
```

## Contributing

Issues and pull requests are welcome. Before opening a PR, please make sure
`mix test`, `mix credo --strict`, and `mix dialyzer` all pass.

## License

MIT — see [LICENSE](LICENSE).
