# Alembic

Alembic is a template engine designed for the Grimoire static site generator.

The project focuses on a small, explicit public API and a zero-runtime-dependency
implementation built with Elixir and OTP standard-library functionality.

> Alembic is currently under development. The compiler and renderer are not yet
> implemented.

## Goals

Alembic aims to provide:

- template compilation separated from rendering;
- clear and documented error handling;
- a small public API;
- zero runtime dependencies;
- reusable compiled templates;
- integration with the Grimoire static site generator.

## Dependency policy

Alembic has zero runtime dependencies.

Development tooling is allowed when it does not become part of the runtime
dependency graph:

- ExDoc generates project documentation;
- Credo performs static code analysis.

Both dependencies are configured with `runtime: false`.

## Planned public API

### Compile a template

```elixir
{:ok, compiled} =
  Alembic.compile("Hello from Alembic!", [])
```

### Render a compiled template
```elixir
{:ok, output} =
  Alembic.render(compiled, %{}, [])
```

### Render a template file
```elixir
{:ok, output} =
  Alembic.render_file("templates/index.alembic", %{}, [])
```

### Bang variants
```elixir
compiled =
  Alembic.compile!("Hello from Alembic!", [])

output =
  Alembic.render!(compiled, %{}, [])
```

The bang variants return the successful value directly and raise when an
operation fails.

These examples represent the intended API. During the initial scaffold
milestone, the non-bang functions return `{:error, :not_implemented}`.

## Alembic and Grimoire

Alembic is developed as an independent library.

During local development, [Grimoire](https://github.com/uminocelo/grimoire_ex) can reference Alembic as a path dependency:

```elixir
defp deps do
  [
    {:alembic, path: "../alembic"}
  ]
end
```

This separation keeps template compilation and rendering independent from the
static site generator's file discovery, content processing, routing, and output
generation.

```bash
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

Install dependencies:

```bash
mix deps.get
```

Run tests:

```bash
mix test
```

Check formatting:
```bash
mix format --check-formatted
```

Run static analysis:
```bash
mix credo
```
Generate documentation:

```bash
mix docs
```
Build the Hex package:

```bash
mix hex.build
```
