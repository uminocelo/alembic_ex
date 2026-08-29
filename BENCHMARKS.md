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
(~49.3 KB, 150 repeated rows: if/else, a nested for loop, a filter chain,
~3,900 tokens / ~1,500 AST nodes)

| Stage | Iterations/sec | Avg time | Median | 99th % | Memory/call |
|---|---|---|---|---|---|
| `lexer_only` (`Lexer.tokenize/1`) | 205.45 | 4.87 ms | 4.78 ms | 5.60 ms | 9.21 MB |
| `parser_only` (`Parser.parse/1`, pre-tokenized) | 534.82 | 1.87 ms | 1.83 ms | 2.21 ms | 2.26 MB |
| `eval_only` (`Evaluator.eval/2`, pre-compiled) | 721.25 | 1.39 ms | 1.36 ms | 1.88 ms | 1.92 MB |
| `full_precompiled` (`Alembic.render/3` on a pre-compiled AST) | 679.04 | 1.47 ms | 1.44 ms | 1.95 ms | 2.07 MB |
| `full_cold` (`Alembic.render_string/3`, tokenize+parse+eval every call) | 116.32 | 8.60 ms | 8.52 ms | 9.61 ms | 13.56 MB |

### Notes

- Lexing is the single most expensive stage (4.87 ms), consistent with the
  per-codepoint DFA walk measured in isolation above — it accounts for
  roughly 57% of `full_cold`'s total time on this fixture.
- `eval_only` and `full_precompiled` are close (1.39 ms vs 1.47 ms) — the
  ~80 μs gap is `Alembic.render/3`'s own overhead: building the `Context`
  and running `Inheritance.preprocess/2` (a no-op flatten pass here, since
  this fixture has no `{% block %}`/`{% extends %}` — see
  `Alembic.Inheritance.preprocess/2`'s moduledoc).
- `full_cold` (8.60 ms) is close to, but not exactly, the sum of the three
  isolated stages (4.87 + 1.87 + 1.39 = 8.13 ms) — the small gap is
  `render_string/3`'s own `compile/2` + `render/3` dispatch overhead.

## Cache: hit vs miss

Script: [`bench/cache_bench.exs`](bench/cache_bench.exs) — `Alembic.render_file/3`
on the same pipeline fixture, `roots: [bench/fixtures]`.

| Scenario | Iterations/sec | Avg time | Median | 99th % | Memory/call |
|---|---|---|---|---|---|
| `cache_hit` (warm cache) | 538.66 | 1.86 ms | 1.80 ms | 2.35 ms | 2.08 MB |
| `cache_miss` (`Cache.clear/0` before every call) | 110.46 | 9.05 ms | 8.99 ms | 9.98 ms | 13.52 MB |

**Cache hit is 4.88x faster than cache miss** — exceeds the ≥3x acceptance
bar. A hit skips `Loader.resolve_path/2` + `File.read/1` + `compile/2`
entirely, landing close to `eval_only`'s own 1.39 ms above (the extra ~0.5 ms
is `Loader.resolve_path/2`'s directory walk plus the `Cache.get/1` ETS
lookup itself).

## iolist vs naive string concatenation

Script: [`bench/iolist_bench.exs`](bench/iolist_bench.exs) — `Alembic.Evaluator`
(real, iolist-accumulating) vs a naive `Enum.reduce(nodes, "", &(&2 <> ...))`
evaluator written only for this comparison (not production code; text and
output nodes only, no filters/control-flow), across four sizes of a
synthetic flat AST.

| Size | iolist ips | naive concat ips | iolist avg | naive avg | iolist mem | naive mem |
|---|---|---|---|---|---|---|
| ~10 output nodes | 228.95 K | 858.15 K | 4.37 μs | 1.17 μs | 6.44 KB | 1.27 KB |
| ~100 output nodes | 24.42 K | 99.19 K | 40.95 μs | 10.08 μs | 62.69 KB | 11.81 KB |
| ~1,000 output nodes | 2.21 K | 10.37 K | 452.35 μs | 96.46 μs | 625.19 KB | 117.28 KB |
| ~50,000 output nodes | 41.06 | 110.15 | 24.36 ms | 9.08 ms | 30.52 MB | 5.72 MB |

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
   predicts: iolist goes from 3.75x slower at 10 nodes down to 2.68x slower
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
below, where `where` alone costs 55x more than `date`. A follow-up
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
| `date` | 1,337.87 K | 0.75 μs | 1.00 KB |
| `truncate` | 356.56 K | 2.80 μs | 5.34 KB |
| `upcase` | 204.42 K | 4.89 μs | 4.70 KB |
| `map` | 166.31 K | 6.01 μs | 3.31 KB |
| `join` | 85.22 K | 11.73 μs | 15.82 KB |
| `where` | 24.14 K | 41.42 μs | 63.41 KB |

`where` is the clear outlier — 55x slower and 63x more memory than `date`.
It walks the full 200-item list calling `item_key/2` (a map lookup plus a
`String.to_existing_atom/1`-guarded fallback) per item, then rebuilds a
filtered list; `map` does similar per-item work but without the equality
check or list-filtering overhead, which is consistent with it being ~7x
cheaper.

### Filter chain length: none vs 1 vs 5

Same ~240-char string; chain is `upcase → downcase → strip → truncate(80) → append("!")`.

| Chain length | Iterations/sec | Avg time | Memory/call |
|---|---|---|---|
| 0 filters | 50,016.80 K | 0.02 μs | 0.02 KB |
| 1 filter | 203.96 K | 4.90 μs | 4.75 KB |
| 5 filters | 72.19 K | 13.85 μs | 21.20 KB |

Cost scales roughly linearly with chain length (≈2.83 μs/filter marginal
cost from 1→5), not the dispatch-per-filter-name overhead one might expect
to dominate — each filter's own work (string traversal, allocation) is the
larger factor once at least one filter is in the chain.
