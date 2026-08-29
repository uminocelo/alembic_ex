assigns = %{
  "site" => %{"title" => "Bench"},
  "user" => %{"active" => true, "name" => "Alice"},
  "total" => 150,
  "status" => "inactive",
  "tags" => ["a", "b", "c"],
  "post" => %{
    "title" => String.duplicate("x", 60),
    "author" => %{"name" => "Bob"},
    "date" => "2024-01-01"
  }
}

opts = [roots: [Path.join(__DIR__, "fixtures")]]

Benchee.run(
  %{
    "cache_miss (Cache.clear/0 before every call)" => fn ->
      Alembic.Cache.clear()
      # Cache.clear/0 is an async cast — sweep/0 is a call sharing the same
      # FIFO mailbox, so waiting for its reply guarantees clear/0 has
      # already been processed before the render_file/3 call below.
      Alembic.Cache.sweep()
      Alembic.render_file("pipeline_template.liquid", assigns, opts)
    end,
    "cache_hit (warm cache)" => fn ->
      Alembic.render_file("pipeline_template.liquid", assigns, opts)
    end
  },
  time: 5,
  memory_time: 2,
  warmup: 2,
  before_scenario: fn input ->
    # Warm the cache once before the cache_hit scenario's measured runs;
    # the cache_miss scenario clears it again on every single iteration.
    Alembic.render_file("pipeline_template.liquid", assigns, opts)
    input
  end
)
