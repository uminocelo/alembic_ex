
# Run with: mix run examples/03_filters.exs
#
# A tour of the built-in filter library (Alembic.Filters). Filters chain
# with `|`, left to right — each filter's output feeds the next.

examples = [
  {~s({{ name | upcase }}), %{"name" => "alice"}},
  # Note: output tags require a variable-path base (optionally filtered) —
  # a bare string literal like {{ "hi" | strip }} isn't supported, so route
  # any literal value through a variable first.
  {~s({{ padded | strip }}), %{"padded" => "  hello  "}},
  {~s({{ title | truncate: 20 }}), %{"title" => "A very long blog post title indeed"}},
  {~s({{ tags | join: ", " }}), %{"tags" => ["elixir", "phoenix", "otp"]}},
  {~s({{ price | plus: tax }}), %{"price" => 19.99, "tax" => 1.5}},
  {~s({{ published_at | date: "%Y-%m-%d" }}), %{"published_at" => ~D[2026-08-29]}},
  {~s({{ bio | default: "No bio yet." }}), %{"bio" => nil}},
  # Chains: each filter's output feeds the next.
  {~s({{ name | strip | upcase | truncate: 10 }}), %{"name" => "  alexandria  "}},
  # Array filters: map + sort + join.
  {~s({{ users | map: "name" | sort | join: ", " }}),
   %{"users" => [%{"name" => "Carol"}, %{"name" => "Alice"}, %{"name" => "Bob"}]}}
]

Enum.each(examples, fn {template, assigns} ->
  {:ok, output} = Alembic.render_string(template, assigns)
  IO.puts("#{template}\n  => #{inspect(output)}\n")
end)
