# Benchmarks

Benchmark numbers vary by machine and are inherently non-deterministic. They
are documentation, not tests, and are not run as part of CI.

## Machine

- CPU: Apple M1 Pro
- RAM: 16 GB
- OS: macOS
- Elixir: 1.18.4
- OTP: 25.3.2.21

## Lexer: `Alembic.Lexer.tokenize/1`

Script: [`bench/lexer_bench.exs`](bench/lexer_bench.exs)
Fixture: [`bench/fixtures/large_template.liquid`](bench/fixtures/large_template.liquid)
(~51.8 KB, 200 repeated rows, ~2,000 output/tag delimiters combined)

| Benchmark | Iterations/sec | Avg time | Median | 99th % | Memory/call |
|---|---|---|---|---|---|
| `tokenize/1` (50 KB fixture) | 189.87 | 5.27 ms | 5.17 ms | 6.05 ms | 9.93 MB |

### Notes

- The lexer walks the input one UTF-8 codepoint at a time (per the
  DFA design in issue 1.2.1) and coalesces adjacent text tokens in a single
  final pass — this is O(n) in input size, and the numbers above are
  consistent with that: ~5.3 ms for ~52 KB of input, i.e. roughly 10 MB/s
  single-threaded throughput on this reference input.
- Memory usage (~10 MB for a 52 KB input) is dominated by the per-character
  text token accumulator before coalescing — this is expected for the
  current implementation and is a candidate area to revisit if the lexer's
  memory profile ever becomes a bottleneck downstream (e.g. in the parser or
  evaluator benchmarks below).

## Full pipeline stages: `Alembic.{Lexer,Parser,Evaluator}` / `Alembic.render*`

Script: [`bench/pipeline_bench.exs`](bench/pipeline_bench.exs)
Fixture: [`bench/fixtures/pipeline_template.liquid`](bench/fixtures/pipeline_template.liquid)
(~49.6 KB, 150 repeated rows: if/else, a nested for loop, a filter chain,
5 `{% include %}` tags pulling in
[`bench/fixtures/includes/snippet.liquid`](bench/fixtures/includes/snippet.liquid),
~3,900 tokens / ~1,500 AST nodes)

| Stage | Iterations/sec | Avg time | Median | 99th % | Memory/call |
|---|---|---|---|---|---|
| `lexer_only` (`Lexer.tokenize/1`) | 168.51 | 5.93 ms | 5.85 ms | 7.04 ms | 10.46 MB |
| `parser_only` (`Parser.parse/1`, pre-tokenized) | 509.53 | 1.96 ms | 1.91 ms | 2.54 ms | 2.31 MB |
| `eval_only` (`Evaluator.eval/2`, pre-compiled) | 564.46 | 1.77 ms | 1.72 ms | 2.33 ms | 2.06 MB |
| `full_precompiled` (`Alembic.render/3` on a pre-compiled AST) | 526.47 | 1.90 ms | 1.83 ms | 2.51 ms | 2.21 MB |
| `full_cold` (`Alembic.render_string/3`, tokenize+parse+eval every call) | 98.51 | 10.15 ms | 10.19 ms | 12.39 ms | 14.91 MB |

### Notes

- Lexing is the single most expensive stage (5.93 ms), consistent with the
  per-codepoint DFA walk measured in isolation above — it accounts for
  roughly 58% of `full_cold`'s total time on this fixture.
- `eval_only` and `full_precompiled` are close (1.77 ms vs 1.90 ms) — the
  ~130 μs gap is `Alembic.render/3`'s own overhead: building the `Context`
  and running `Inheritance.preprocess/2` (a no-op flatten pass here, since
  this fixture has no `{% block %}`/`{% extends %}` — see
  `Alembic.Inheritance.preprocess/2`'s moduledoc).
- `full_cold` (10.15 ms) is close to, but not exactly, the sum of the three
  isolated stages (5.93 + 1.96 + 1.77 = 9.66 ms) — the small gap is
  `render_string/3`'s own `compile/2` + `render/3` dispatch overhead.
- Both `eval_only` and `full_precompiled` now pay the cost of resolving this
  fixture's 5 `{% include %}` tags on every single call — see the finding
  below, which is exactly what running this fixture's includes through the
  cache benchmark surfaced.

## Cache: hit vs miss

Script: [`bench/cache_bench.exs`](bench/cache_bench.exs) — `Alembic.render_file/3`
on the same pipeline fixture, `roots: [bench/fixtures]`.

| Scenario | Iterations/sec | Avg time | Median | 99th % | Memory/call |
|---|---|---|---|---|---|
| `cache_hit` (warm cache) | 440.85 | 2.27 ms | 2.21 ms | 3.03 ms | 2.22 MB |
| `cache_miss` (`Cache.clear/0` before every call) | 94.41 | 10.59 ms | 10.55 ms | 11.90 ms | 15.05 MB |

**Cache hit is 4.67x faster than cache miss** — exceeds the ≥3x acceptance
bar, but is below the 5–20x expectation in this issue's task list. Two
things were investigated:

1. **`Alembic.Cache.get/1`'s `Logger.debug/1` calls were changed to the
   lazy `Logger.debug(fn -> ... end)` form** (`lib/alembic/cache.ex`), so
   the `"Alembic.Cache hit: #{path}"` string is only built when the
   configured Logger level would actually emit it, instead of on every
   single call regardless. This is strictly correct practice for a hot
   path, but re-running the benchmark before and after showed no
   measurable change (both within this benchmark's own ~9% run-to-run
   noise) — `:ets.lookup/2` plus the full re-render below it dominates the
   hit path so completely that a few microseconds of string interpolation
   was never going to move a millisecond-scale number.
2. **The real reason the ratio isn't higher: a cache hit still means "skip
   recompiling the *top-level* template," not "skip recompiling
   everything."** `Alembic.Evaluator`'s internal include-compilation step
   calls `Lexer.tokenize/1` + `Parser.parse/1` directly on every `{% include %}`
   it encounters, on every single render, uncached — `Alembic.Cache` only
   ever sees the outer template's path. This fixture's 5 includes (of a
   tiny, ~50-byte partial) are recompiled from scratch 5 times per
   `cache_hit` iteration. This didn't show up before because the pipeline
   fixture had **zero** `{% include %}` tags (a gap this same audit pass
   fixed) — a benchmark can only surface a cost that its fixture actually
   pays. Caching compiled partials is a real, legitimate follow-up (not
   attempted here — it would mean either a separate cache keyed by include
   path, or extending `Alembic.Cache`'s existing key space), but is a
   feature change beyond this benchmarking issue's scope.

A cache hit still skips `Loader.resolve_path/2` + `File.read/1` +
`compile/2` for the outer template entirely, landing close to `eval_only`'s
own 1.77 ms above (the extra ~0.5 ms is `Loader.resolve_path/2`'s directory
walk plus the `Cache.get/1` ETS lookup itself).

## iolist vs naive string concatenation

Script: [`bench/iolist_bench.exs`](bench/iolist_bench.exs) — `Alembic.Evaluator`
(real, iolist-accumulating) vs a naive `Enum.reduce(nodes, "", &(&2 <> ...))`
evaluator written only for this comparison (not production code; text and
output nodes only, no filters/control-flow), across four sizes of a
synthetic flat AST.

| Size | iolist ips | naive concat ips | iolist avg | naive avg | iolist mem | naive mem |
|---|---|---|---|---|---|---|
| ~10 output nodes | 215.97 K | 822.87 K | 4.63 μs | 1.22 μs | 6.52 KB | 1.27 KB |
| ~100 output nodes | 23.06 K | 97.38 K | 43.37 μs | 10.27 μs | 63.47 KB | 11.81 KB |
| ~1,000 output nodes | 2.07 K | 10.24 K | 484.22 μs | 97.69 μs | 633.02 KB | 117.28 KB |
| ~50,000 output nodes | 35.18 | 107.62 | 28.43 ms | 9.29 ms | 30.90 MB | 5.72 MB |

### This result contradicts the assumption in issue 1.4.2/1.5.6 — documented, not hidden

The expectation going in (per issue 1.5.6: "iolist should be ~10x faster at
scale") was that iolist accumulation would beat naive `<>` concatenation,
increasingly so as size grows. **The measured result is the opposite at
every size tested**, from 10 nodes up to 50,000: naive string concatenation
is consistently faster and uses less memory than `Alembic.Evaluator`'s real
iolist-based path.

Two things are true at once, and both matter for reading this table
correctly:

1. **The gap *is* narrowing with scale**, exactly as the O(n²) concat theory
   predicts: iolist goes from 3.80x slower at 10 nodes down to 3.06x slower
   at 50,000. If this trend continues, naive concatenation's relative cost
   should keep climbing at larger sizes still — this benchmark's largest
   tier (50,000 nodes / a multi-MB rendered output) simply isn't large
   enough to reach the crossover point on the BEAM, whose binary
   implementation (reference-counted, copy-on-write "refc binaries") makes
   single-accumulator `<>` concatenation considerably cheaper in practice
   than the classic "O(n²) string building" warning assumes for other
   runtimes.
2. **The naive evaluator in this benchmark is not doing the same amount of
   work as the real one.** It skips `Context.resolve_path/2` (map/keyword
   traversal with atom-safety fallback), `Filters.apply_chain/3` (called,
   even for an empty filter list, via `Enum.reduce_while/3`), and the
   multi-clause `eval_node`/`eval_expr` dispatch. At the sizes tested here,
   *that* fixed per-node overhead — not the accumulation strategy — is the
   dominant cost, and it affects both evaluators' "real work" identically
   in production but only exists in the real one in this comparison.

**Conclusion:** this benchmark does not validate "iolist is faster" as
written, and the acceptance criterion asking for that validation is not
met. It does show that per-node evaluation overhead (`Context.resolve_path/2`
and the filter-chain call in particular) is a more promising target for
future optimization work than the accumulation strategy — see `filter_bench.exs`
below, where `where` alone costs 53x more than `date`. A follow-up
benchmark isolating `Context.resolve_path/2` and `Filters.apply_chain/3`
from the accumulation strategy (i.e. two evaluators that both skip filters/
context, differing *only* in `<>` vs iolist) would be needed to properly
answer the original question.

## Filter chain throughput

Script: [`bench/filter_bench.exs`](bench/filter_bench.exs)

### Individual filters

200-item list of maps for `map`/`where`/`join`; a ~240-char string for
`upcase`/`truncate`; a `Date` struct for `date`.

| Filter | Iterations/sec | Avg time | Memory/call |
|---|---|---|---|
| `date` | 1,264.52 K | 0.79 μs | 1.00 KB |
| `truncate` | 332.00 K | 3.01 μs | 5.34 KB |
| `upcase` | 198.32 K | 5.04 μs | 4.70 KB |
| `map` | 162.74 K | 6.14 μs | 3.31 KB |
| `join` | 84.52 K | 11.83 μs | 15.82 KB |
| `where` | 23.65 K | 42.28 μs | 63.41 KB |

`where` is the clear outlier — 53x slower and 63x more memory than `date`.
It walks the full 200-item list calling `item_key/2` (a map lookup plus a
`String.to_existing_atom/1`-guarded fallback) per item, then rebuilds a
filtered list; `map` does similar per-item work but without the equality
check or list-filtering overhead, which is consistent with it being ~7x
cheaper.

### Filter chain length: none vs 1 vs 5

Same ~240-char string; chain is `upcase → downcase → strip → truncate(80) → append("!")`.

| Chain length | Iterations/sec | Avg time | Memory/call |
|---|---|---|---|
| 0 filters | 47,046.96 K | 0.02 μs | 0.02 KB |
| 1 filter | 196.36 K | 5.09 μs | 4.76 KB |
| 5 filters | 68.45 K | 14.61 μs | 21.20 KB |

Cost scales roughly linearly with chain length (≈2.38 μs/filter marginal
cost from 1→5), not the dispatch-per-filter-name overhead one might expect
to dominate — each filter's own work (string traversal, allocation) is the
larger factor once at least one filter is in the chain.
