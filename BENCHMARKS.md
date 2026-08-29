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
  evaluator benchmarks planned for Milestone 1.5).
