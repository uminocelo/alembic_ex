
# Run with: mix run examples/04_custom_filter.exs
#
# Register a custom filter by implementing the Alembic.Filter behaviour,
# then either list the module in `config :alembic, custom_filters: [...]`
# (global, every render call) or pass `custom_filters: [...]` as a
# render/3 (or render_string/3, render_file/3) option (per call only).

defmodule Examples.Filters.Money do
  @behaviour Alembic.Filter

  @impl true
  def name, do: "money"

  @impl true
  def apply(cents, []) when is_integer(cents) do
    {:ok, "$" <> :erlang.float_to_binary(cents / 100, decimals: 2)}
  end

  def apply(_value, _args), do: {:error, :expected_integer_cents}
end

Application.put_env(:alembic, :custom_filters, [Examples.Filters.Money])

{:ok, output} = Alembic.render_string("Total: {{ price_cents | money }}", %{"price_cents" => 1999})
IO.puts(output)
# => Total: $19.99

# Custom filters are checked before the built-in catalog, but don't shadow
# filters they don't define — "upcase" still resolves to the built-in.
{:ok, output} = Alembic.render_string("{{ name | upcase }}: {{ price_cents | money }}", %{
  "name" => "coffee",
  "price_cents" => 450
})

IO.puts(output)
# => COFFEE: $4.50

Application.delete_env(:alembic, :custom_filters)

# --- Per-call custom filters (no global config at all) ---
#
# Pass `custom_filters: [...]` as an option instead of touching
# `Application.put_env/3` — useful when the filter only applies to one
# call site (a single template, a single request) rather than the whole
# app. Per-call modules are tried before the global list, so they take
# precedence on a name collision, but nothing here requires a global list
# to exist at all.

defmodule Examples.Filters.Shout do
  @behaviour Alembic.Filter

  @impl true
  def name, do: "shout"

  @impl true
  def apply(value, []) when is_binary(value), do: {:ok, String.upcase(value) <> "!"}
end

{:ok, output} =
  Alembic.render_string("{{ name | shout }}", %{"name" => "world"},
    custom_filters: [Examples.Filters.Shout]
  )

IO.puts(output)
# => WORLD!

# Without the option, "shout" is simply unknown — it was never registered
# globally, only for the one call above.
IO.inspect(Alembic.render_string("{{ name | shout }}", %{"name" => "world"}))
# => {:error, {:evaluator, {:unknown_filter, "shout"}}}
