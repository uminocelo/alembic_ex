alias Alembic.Filters

string_value = String.duplicate("hello world ", 20)
list_value = for i <- 1..200, do: %{"title" => "item-#{i}", "featured" => rem(i, 3) == 0}
date_value = ~D[2024-06-15]

IO.puts("=== Individual filters ===")

Benchee.run(
  %{
    "upcase" => fn -> Filters.apply("upcase", string_value, []) end,
    "truncate" => fn -> Filters.apply("truncate", string_value, [50]) end,
    "join" => fn -> Filters.apply("join", Enum.map(list_value, & &1["title"]), [", "]) end,
    "map" => fn -> Filters.apply("map", list_value, ["title"]) end,
    "where" => fn -> Filters.apply("where", list_value, ["featured", true]) end,
    "date" => fn -> Filters.apply("date", date_value, ["%Y-%m-%d"]) end
  },
  time: 3,
  memory_time: 1,
  warmup: 1
)

IO.puts("\n=== Filter chain length: none vs 1 vs 5 ===")

Benchee.run(
  %{
    "no filters" => fn -> {:ok, string_value} end,
    "1 filter" => fn -> Filters.apply_chain(string_value, [{"upcase", []}], nil) end,
    "5 filters" => fn ->
      Filters.apply_chain(
        string_value,
        [
          {"upcase", []},
          {"downcase", []},
          {"strip", []},
          {"truncate", [80]},
          {"append", ["!"]}
        ],
        nil
      )
    end
  },
  time: 3,
  memory_time: 1,
  warmup: 1
)
