# Liquid Compatibility

Alembic implements a Liquid-compatible subset of the template language. This
document lists what's supported, where Alembic intentionally deviates from
upstream Liquid, what's entirely out of scope for this MVP, and what
Alembic adds beyond Liquid.

Note on methodology: this session had no network access to fetch and port
Shopify's actual `github.com/Shopify/liquid` test-suite fixtures. Coverage
of the same *categories* the official suite exercises (variables, if/for,
assign, filters, whitespace control, comments, raw blocks) is instead
hand-written in `test/integration/liquid_compat_test.exs`.

---

## Supported Liquid features

- **Output tags** — `{{ user.name }}`, dot-path and bracket (`user["name"]`)
  variable access, both interchangeable.
- **Filters** — full pipe chain syntax (`{{ x | a | b: 1, 2 }}`); see
  `Alembic.Filters` for the complete catalog (string, array, number, misc).
- **Control flow** — `{% if %}` / `{% elsif %}` / `{% else %}` /
  `{% endif %}`, `{% for %}` / `{% else %}` / `{% endfor %}` with full
  `forloop` metadata (`index`, `index0`, `rindex`, `rindex0`, `first`,
  `last`, `length`).
- **Operators** — `==`, `!=`, `>`, `<`, `>=`, `<=`, `contains`, `and`, `or`,
  `not`, with `not > and > or` precedence (see `docs/grammar.md` §5.4).
- **Assignment** — `{% assign var = expr %}`, visible to every node
  evaluated after it, including across `{% for %}`/`{% if %}` boundaries.
- **Whitespace control** — `{{-`, `-}}`, `{%-`, `-%}` in any combination.
- **Comments** — `{% comment %} ... {% endcomment %}`, content fully
  discarded, including anything that looks like Liquid syntax inside it.
- **Raw blocks** — `{% raw %} ... {% endraw %}`, content preserved verbatim
  as plain text.
- **Template inheritance** — `{% extends %}` / `{% block %}` /
  `{% endblock %}`, multi-level chains, `{{ block.super }}`, circular- and
  max-depth detection.
- **Includes** — `{% include "partial.html" %}` and
  `{% include "partial.html" with key: val, key2: val2 %}`, sharing the
  including template's scope (classic `include` semantics, not an isolated
  `render`).
- **Liquid truthiness** — only `nil` and `false` are falsy; `0`, `""`, and
  `[]` are all truthy, matching Liquid (not Elixir's own truthiness rules).

## Intentional deviations

| Area | Alembic | Upstream Liquid | Why |
|---|---|---|---|
| `join` with no argument | separator `""` | separator `" "` | Issue 1.4.3's own task list specified `""` explicitly |
| `url_encode` / `url_decode` | `URI.encode_www_form/1` (space → `+`) | same (`+` for space) | Matches Liquid; `URI.encode/1` (percent-encodes space as `%20`) would not have |
| `ceil` / `floor` | return integers | return integers | Matches Liquid; Elixir's own `Float.ceil/1` returns a float, so this required an explicit `trunc/1` |
| `date` filter | Elixir `Calendar.strftime/2` format strings | Ruby `strftime` format strings | No Ruby-compatible formatter available without a dependency; the two format-string dialects are similar but not identical |
| Output tag base expression | must be a bare variable path (optionally filtered) | any expression, including literals | `Alembic.AST.output_node`'s type (`{:output, path(), [filter()]}`) was fixed in Milestone 1.1, before the parser existed; `{{ "literal" \| filter }}` returns `{:error, {:unsupported_output_expression, _}}` |
| Cache hit/miss telemetry | `Logger.debug/1` | n/a | `:telemetry` is a separate Hex package; issue 1.1.1's zero-runtime-deps policy (ex_doc only) rules it out |
| `slice` filter | strings only | strings and arrays | `Alembic.Filters`' `slice` clauses always run the input through `coerce_to_string/1`; array slicing was never implemented |

## Unsupported features (out of MVP scope)

- `{% tablerow %}` tag
- `{% paginate %}` tag (and the wider Shopify pagination object)
- Liquid's built-in request/shop/theme objects (`request`, `shop`, `theme`,
  etc.) — Alembic has no notion of these; all context comes from the
  `assigns` map passed to `render/3`
- `{% render %}` (isolated-scope include) — only classic `{% include %}`
  (shared scope) exists
- `{% cycle %}`, `{% increment %}`, `{% decrement %}` tags
- Liquid's `{% liquid %}` shorthand block syntax
- Ranges as iterables (`{% for i in (1..5) %}`) — `{% for %}` only accepts
  an array-valued expression, not an inline range literal
- Multi-argument `{% assign %}` expressions beyond a single filter chain

## Extension features (Alembic adds beyond Liquid)

- `base64_encode` / `base64_decode` filters
- `Alembic.Filter` behaviour for registering custom filters, globally via
  `config :alembic, custom_filters: [MyApp.Filters.Money]` or per call via
  `render/3`'s `custom_filters:` option (the latter takes precedence on a
  name collision)
- `strict: true` render option — errors on any undefined variable instead of
  silently rendering `""`, useful for catching typos during development
- ETS-backed compiled-template cache with mtime-based invalidation,
  `sweep/0` for pruning stale entries, and a `cache: false` per-call opt to
  bypass it
- Path-traversal protection built into the file loader (`{:path_traversal_detected, _}`)
