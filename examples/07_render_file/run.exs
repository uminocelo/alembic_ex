
# Run with: mix run examples/07_render_file/run.exs
#
# render_file/3 loads a template from disk, compiles it, and caches the
# compiled AST (Alembic.Cache) keyed by the file's resolved path + mtime.
# A second render_file/3 call for the same file skips tokenizing and
# parsing entirely.

root = Path.join(__DIR__, "templates")
opts = [roots: [root]]

# Cache.put/2 is an async cast — Cache.sweep/0 is a synchronous call that
# shares the same FIFO mailbox, so waiting for its reply guarantees any
# prior cast has already been processed. Only needed here because we're
# about to inspect Cache.get/1 directly; render_file/3 itself doesn't need
# this — it always compiles on a genuine miss regardless of cast timing.
sync = fn -> Alembic.Cache.sweep() end

{:ok, resolved_path} = Alembic.Loader.resolve_path("greeting.html", opts)

IO.inspect(Alembic.Cache.get(resolved_path), label: "cache before first render")

{first_us, {:ok, output1}} =
  :timer.tc(fn -> Alembic.render_file("greeting.html", %{"name" => "Ada"}, opts) end)

sync.()
IO.inspect(Alembic.Cache.get(resolved_path), label: "cache after first render")

{second_us, {:ok, output2}} =
  :timer.tc(fn -> Alembic.render_file("greeting.html", %{"name" => "Grace"}, opts) end)

IO.puts(output1)
IO.puts(output2)
IO.puts("first call (cold, tokenizes + parses):  #{first_us} µs")
IO.puts("second call (warm, cache hit):          #{second_us} µs")

# cache: false bypasses the cache for a single call, without disabling it
# globally — useful for e.g. a "preview" endpoint that must always reflect
# the latest file on disk.
{:ok, _output} = Alembic.render_file("greeting.html", %{"name" => "Uncached"}, opts ++ [cache: false])
