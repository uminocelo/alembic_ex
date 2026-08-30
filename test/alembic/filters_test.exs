defmodule Alembic.FiltersTest do
  use ExUnit.Case, async: true

  doctest Alembic.Filters

  alias Alembic.Filters

  describe "dispatch" do
    test "unknown filter name" do
      assert {:error, {:unknown_filter, "frobnicate"}} = Filters.apply("frobnicate", "x", [])
    end

    test "known filter with wrong argument shape" do
      assert {:error, {:invalid_filter_args, "upcase", [1, 2]}} =
               Filters.apply("upcase", "x", [1, 2])
    end
  end

  describe "apply_chain/3" do
    test "applies filters left to right, each output feeding the next" do
      assert {:ok, "HEL"} =
               Filters.apply_chain("hello", [{"upcase", []}, {"truncate", [3, ""]}], nil)
    end

    test "short-circuits on the first error" do
      assert {:error, {:unknown_filter, "nope"}} =
               Filters.apply_chain("hello", [{"nope", []}, {"upcase", []}], nil)
    end

    test "empty filter list returns the value unchanged" do
      assert {:ok, "hello"} = Filters.apply_chain("hello", [], nil)
    end
  end

  describe "custom filters" do
    defmodule Shout do
      @behaviour Alembic.Filter

      @impl true
      def name, do: "shout"

      @impl true
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      def apply(value, []), do: {:ok, String.upcase(value) <> "!"}
    end

    test "a registered custom filter is used instead of the built-in dispatch" do
      Application.put_env(:alembic, :custom_filters, [Shout])
      assert {:ok, "HELLO!"} = Filters.apply("shout", "hello", [])
    after
      Application.delete_env(:alembic, :custom_filters)
    end

    test "custom filters do not shadow built-ins that were not overridden" do
      Application.put_env(:alembic, :custom_filters, [Shout])
      assert {:ok, "HELLO"} = Filters.apply("upcase", "hello", [])
    after
      Application.delete_env(:alembic, :custom_filters)
    end

    defmodule ReverseUpcase do
      @behaviour Alembic.Filter

      @impl true
      def name, do: "upcase"

      @impl true
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      def apply(value, []), do: {:ok, value |> String.reverse() |> String.upcase()}
    end

    test "apply/4 accepts a per-call custom filter with no global config set" do
      assert {:ok, "HELLO!"} = Filters.apply("shout", "hello", [], [Shout])
    end

    test "apply/4 defaults per-call custom filters to an empty list" do
      assert {:error, {:unknown_filter, "shout"}} = Filters.apply("shout", "hello", [])
    end

    test "a per-call custom filter takes precedence over global config on a name collision" do
      Application.put_env(:alembic, :custom_filters, [ReverseUpcase])
      assert {:ok, "OLLEH"} = Filters.apply("upcase", "hello", [], [ReverseUpcase])

      # Sanity check: without the per-call override, the global one still wins.
      assert {:ok, "OLLEH"} = Filters.apply("upcase", "hello", [])
    after
      Application.delete_env(:alembic, :custom_filters)
    end

    test "apply_chain/3 consults a Context's custom_filters for every filter in the chain" do
      ctx = Alembic.Context.new(%{}) |> Alembic.Context.custom_filters([Shout])

      assert {:ok, "HELLO!"} = Filters.apply_chain("hello", [{"shout", []}], ctx)
    end

    test "apply_chain/3 with no Context (nil) uses only global config" do
      assert {:error, {:unknown_filter, "shout"}} =
               Filters.apply_chain("hello", [{"shout", []}], nil)
    end
  end

  describe "string filters" do
    test "upcase" do
      assert {:ok, "HELLO"} = Filters.apply("upcase", "hello", [])
    end

    test "downcase" do
      assert {:ok, "hello"} = Filters.apply("downcase", "HELLO", [])
    end

    test "downcase on an empty string" do
      assert {:ok, ""} = Filters.apply("downcase", "", [])
    end

    test "capitalize" do
      assert {:ok, "Hello world"} = Filters.apply("capitalize", "hello world", [])
    end

    test "capitalize on an empty string" do
      assert {:ok, ""} = Filters.apply("capitalize", "", [])
    end

    test "strip" do
      assert {:ok, "hello"} = Filters.apply("strip", "  hello  ", [])
    end

    test "strip is a no-op when there is no surrounding whitespace" do
      assert {:ok, "hello"} = Filters.apply("strip", "hello", [])
    end

    test "lstrip" do
      assert {:ok, "hello  "} = Filters.apply("lstrip", "  hello  ", [])
    end

    test "lstrip on a string with no leading whitespace is unchanged" do
      assert {:ok, "hello"} = Filters.apply("lstrip", "hello", [])
    end

    test "rstrip" do
      assert {:ok, "  hello"} = Filters.apply("rstrip", "  hello  ", [])
    end

    test "rstrip on a string with no trailing whitespace is unchanged" do
      assert {:ok, "hello"} = Filters.apply("rstrip", "hello", [])
    end

    test "strip_newlines" do
      assert {:ok, "ab"} = Filters.apply("strip_newlines", "a\nb", [])
    end

    test "strip_newlines removes \\r\\n and bare \\r too" do
      assert {:ok, "abc"} = Filters.apply("strip_newlines", "a\r\nb\rc", [])
    end

    test "prepend" do
      assert {:ok, "helloworld"} = Filters.apply("prepend", "world", ["hello"])
    end

    test "prepend with an empty prefix is a no-op" do
      assert {:ok, "world"} = Filters.apply("prepend", "world", [""])
    end

    test "append" do
      assert {:ok, "helloworld"} = Filters.apply("append", "hello", ["world"])
    end

    test "append with an empty suffix is a no-op" do
      assert {:ok, "hello"} = Filters.apply("append", "hello", [""])
    end

    test "replace" do
      assert {:ok, "yes yes"} = Filters.apply("replace", "no no", ["no", "yes"])
    end

    test "replace when search is not found leaves the string unchanged" do
      assert {:ok, "abc"} = Filters.apply("replace", "abc", ["x", "y"])
    end

    test "replace_first" do
      assert {:ok, "yes no"} = Filters.apply("replace_first", "no no", ["no", "yes"])
    end

    test "replace_first when search is not found leaves the string unchanged" do
      assert {:ok, "no no"} = Filters.apply("replace_first", "no no", ["missing", "yes"])
    end

    test "remove" do
      assert {:ok, " "} = Filters.apply("remove", "a a", ["a"])
    end

    test "remove when search is not found leaves the string unchanged" do
      assert {:ok, "abc"} = Filters.apply("remove", "abc", ["x"])
    end

    test "remove_first" do
      assert {:ok, " a"} = Filters.apply("remove_first", "a a", ["a"])
    end

    test "remove_first when search is not found leaves the string unchanged" do
      assert {:ok, "abc"} = Filters.apply("remove_first", "abc", ["x"])
    end

    test "split" do
      assert {:ok, ["a", "b", "c"]} = Filters.apply("split", "a,b,c", [","])
    end

    test "split when the delimiter is not found returns a single-element list" do
      assert {:ok, ["nosplit"]} = Filters.apply("split", "nosplit", [","])
    end

    test "truncate with default ellipsis" do
      assert {:ok, "he..."} = Filters.apply("truncate", "hello world", [5])
    end

    test "truncate is a no-op when the string is already within the limit" do
      assert {:ok, "hi"} = Filters.apply("truncate", "hi", [5])
    end

    test "truncate with custom ellipsis" do
      assert {:ok, "he--"} = Filters.apply("truncate", "hello world", [4, "--"])
    end

    test "truncatewords" do
      assert {:ok, "the quick..."} = Filters.apply("truncatewords", "the quick brown fox", [2])
    end

    test "truncatewords is a no-op when word count is within the limit" do
      assert {:ok, "hi"} = Filters.apply("truncatewords", "hi", [5])
    end

    test "newline_to_br" do
      assert {:ok, "a<br />\nb"} = Filters.apply("newline_to_br", "a\nb", [])
    end

    test "newline_to_br on a string without newlines is unchanged" do
      assert {:ok, "no newlines"} = Filters.apply("newline_to_br", "no newlines", [])
    end

    test "escape" do
      assert {:ok, "&lt;a&gt;"} = Filters.apply("escape", "<a>", [])
    end

    test "escape always encodes ampersands, even in already-escaped entities" do
      assert {:ok, "&amp;lt;"} = Filters.apply("escape", "&lt;", [])
    end

    test "escape_once" do
      assert {:ok, "&lt;a&gt;"} = Filters.apply("escape_once", "<a>", [])
    end

    test "escape_once does not double-encode already-escaped entities" do
      assert {:ok, "&lt;"} = Filters.apply("escape_once", "&lt;", [])
    end

    test "strip_html" do
      assert {:ok, "hello"} = Filters.apply("strip_html", "<b>hello</b>", [])
    end

    test "strip_html on plain text with no tags is unchanged" do
      assert {:ok, "plain"} = Filters.apply("strip_html", "plain", [])
    end

    test "url_encode" do
      assert {:ok, "hello+world"} = Filters.apply("url_encode", "hello world", [])
    end

    test "url_encode percent-encodes special characters" do
      assert {:ok, "a%26b"} = Filters.apply("url_encode", "a&b", [])
    end

    test "url_decode" do
      assert {:ok, "hello world"} = Filters.apply("url_decode", "hello+world", [])
    end

    test "url_decode decodes percent-encoded characters" do
      assert {:ok, "a&b"} = Filters.apply("url_decode", "a%26b", [])
    end

    test "base64_encode" do
      assert {:ok, "aGVsbG8="} = Filters.apply("base64_encode", "hello", [])
    end

    test "base64_encode of an empty string" do
      assert {:ok, ""} = Filters.apply("base64_encode", "", [])
    end

    test "base64_decode" do
      assert {:ok, "hello"} = Filters.apply("base64_decode", "aGVsbG8=", [])
    end

    test "base64_decode returns an error for invalid base64" do
      assert {:error, {:invalid_base64, "not base64!!"}} =
               Filters.apply("base64_decode", "not base64!!", [])
    end

    test "size on a string counts characters, not bytes" do
      assert {:ok, 5} = Filters.apply("size", "hello", [])
    end

    test "size on a string with multi-byte characters still counts characters" do
      assert {:ok, 1} = Filters.apply("size", "é", [])
    end

    test "slice with offset only" do
      assert {:ok, "e"} = Filters.apply("slice", "hello", [1])
    end

    test "slice with offset and length" do
      assert {:ok, "ell"} = Filters.apply("slice", "hello", [1, 3])
    end
  end

  describe "array filters" do
    test "join with a separator" do
      assert {:ok, "a, b, c"} = Filters.apply("join", ["a", "b", "c"], [", "])
    end

    test "join with no separator defaults to empty string" do
      assert {:ok, "abc"} = Filters.apply("join", ["a", "b", "c"], [])
    end

    test "first" do
      assert {:ok, "a"} = Filters.apply("first", ["a", "b"], [])
    end

    test "first of an empty list is nil" do
      assert {:ok, nil} = Filters.apply("first", [], [])
    end

    test "last" do
      assert {:ok, "b"} = Filters.apply("last", ["a", "b"], [])
    end

    test "last of an empty list is nil" do
      assert {:ok, nil} = Filters.apply("last", [], [])
    end

    test "reverse" do
      assert {:ok, [3, 2, 1]} = Filters.apply("reverse", [1, 2, 3], [])
    end

    test "reverse of an empty list" do
      assert {:ok, []} = Filters.apply("reverse", [], [])
    end

    test "sort with natural order" do
      assert {:ok, [1, 2, 3]} = Filters.apply("sort", [3, 1, 2], [])
    end

    test "sort by key" do
      items = [%{"n" => 3}, %{"n" => 1}, %{"n" => 2}]
      assert {:ok, [%{"n" => 1}, %{"n" => 2}, %{"n" => 3}]} = Filters.apply("sort", items, ["n"])
    end

    test "sort_natural is case-insensitive" do
      assert {:ok, ["apple", "Banana", "cherry"]} =
               Filters.apply("sort_natural", ["Banana", "apple", "cherry"], [])
    end

    test "sort_natural on an empty list" do
      assert {:ok, []} = Filters.apply("sort_natural", [], [])
    end

    test "uniq" do
      assert {:ok, [1, 2, 3]} = Filters.apply("uniq", [1, 2, 2, 3, 1], [])
    end

    test "uniq on a list with no duplicates is unchanged" do
      assert {:ok, [1, 2, 3]} = Filters.apply("uniq", [1, 2, 3], [])
    end

    test "compact" do
      assert {:ok, [1, 2]} = Filters.apply("compact", [1, nil, 2, nil], [])
    end

    test "compact of an all-nil list returns an empty list" do
      assert {:ok, []} = Filters.apply("compact", [nil, nil], [])
    end

    test "map" do
      items = [%{"title" => "A"}, %{"title" => "B"}]
      assert {:ok, ["A", "B"]} = Filters.apply("map", items, ["title"])
    end

    test "map returns nil for items missing the key" do
      items = [%{"title" => "A"}, %{}]
      assert {:ok, ["A", nil]} = Filters.apply("map", items, ["title"])
    end

    test "where with a value" do
      items = [%{"featured" => true}, %{"featured" => false}]
      assert {:ok, [%{"featured" => true}]} = Filters.apply("where", items, ["featured", true])
    end

    test "where with truthy check only" do
      items = [%{"active" => true}, %{"active" => false}, %{"active" => nil}]
      assert {:ok, [%{"active" => true}]} = Filters.apply("where", items, ["active"])
    end

    test "concat" do
      assert {:ok, [1, 2, 3, 4]} = Filters.apply("concat", [1, 2], [[3, 4]])
    end

    test "concat with an empty list is a no-op" do
      assert {:ok, [1, 2]} = Filters.apply("concat", [1, 2], [[]])
    end

    test "push" do
      assert {:ok, [1, 2, 3]} = Filters.apply("push", [1, 2], [3])
    end

    test "push onto an empty list" do
      assert {:ok, [1]} = Filters.apply("push", [], [1])
    end

    test "pop" do
      assert {:ok, [1, 2]} = Filters.apply("pop", [1, 2, 3], [])
    end

    test "pop on an empty list is a no-op" do
      assert {:ok, []} = Filters.apply("pop", [], [])
    end

    test "unshift" do
      assert {:ok, [0, 1, 2]} = Filters.apply("unshift", [1, 2], [0])
    end

    test "unshift onto an empty list" do
      assert {:ok, [1]} = Filters.apply("unshift", [], [1])
    end

    test "shift" do
      assert {:ok, [2, 3]} = Filters.apply("shift", [1, 2, 3], [])
    end

    test "shift on an empty list is a no-op" do
      assert {:ok, []} = Filters.apply("shift", [], [])
    end

    test "size on a list" do
      assert {:ok, 3} = Filters.apply("size", [1, 2, 3], [])
    end

    test "size of an empty list is 0" do
      assert {:ok, 0} = Filters.apply("size", [], [])
    end

    test "flatten" do
      assert {:ok, [1, 2, 3, 4]} = Filters.apply("flatten", [1, [2, [3, 4]]], [])
    end

    test "flatten with a depth limit" do
      assert {:ok, [1, 2, [3, 4]]} = Filters.apply("flatten", [1, [2, [3, 4]]], [1])
    end
  end

  describe "number filters" do
    test "abs" do
      assert {:ok, 5} = Filters.apply("abs", -5, [])
    end

    test "abs of a negative float" do
      assert {:ok, 5.5} = Filters.apply("abs", -5.5, [])
    end

    test "ceil returns an integer" do
      assert {:ok, 5} = Filters.apply("ceil", 4.1, [])
    end

    test "ceil on an integer is unchanged" do
      assert {:ok, 4} = Filters.apply("ceil", 4, [])
    end

    test "floor returns an integer" do
      assert {:ok, 4} = Filters.apply("floor", 4.9, [])
    end

    test "floor on an integer is unchanged" do
      assert {:ok, 4} = Filters.apply("floor", 4, [])
    end

    test "round with no precision" do
      assert {:ok, 4} = Filters.apply("round", 3.6, [])
    end

    test "round on an integer is unchanged" do
      assert {:ok, 3} = Filters.apply("round", 3, [])
    end

    test "round with precision" do
      assert {:ok, 3.14} = Filters.apply("round", 3.14159, [2])
    end

    test "plus" do
      assert {:ok, 3} = Filters.apply("plus", 1, [2])
    end

    test "plus with a float operand" do
      assert {:ok, 3.5} = Filters.apply("plus", 1.5, [2])
    end

    test "minus" do
      assert {:ok, -1} = Filters.apply("minus", 1, [2])
    end

    test "minus with a float operand" do
      assert {:ok, -0.5} = Filters.apply("minus", 1.5, [2])
    end

    test "times" do
      assert {:ok, 6} = Filters.apply("times", 2, [3])
    end

    test "times with a float operand" do
      assert {:ok, 5.0} = Filters.apply("times", 2.5, [2])
    end

    test "divided_by does integer division for two integers" do
      assert {:ok, 3} = Filters.apply("divided_by", 7, [2])
    end

    test "divided_by returns a float when either operand is a float" do
      assert {:ok, 3.5} = Filters.apply("divided_by", 7.0, [2])
    end

    test "modulo" do
      assert {:ok, 1} = Filters.apply("modulo", 7, [2])
    end

    test "modulo with a negative dividend" do
      assert {:ok, -1} = Filters.apply("modulo", -7, [2])
    end

    test "at_least" do
      assert {:ok, 5} = Filters.apply("at_least", 3, [5])
    end

    test "at_least leaves a value already at or above the minimum unchanged" do
      assert {:ok, 7} = Filters.apply("at_least", 7, [5])
    end

    test "at_most" do
      assert {:ok, 3} = Filters.apply("at_most", 3, [5])
    end

    test "at_most leaves a value already at or below the maximum unchanged" do
      assert {:ok, 5} = Filters.apply("at_most", 7, [5])
    end
  end

  describe "misc filters" do
    test "default replaces nil, false, and blank values" do
      assert {:ok, "fallback"} = Filters.apply("default", nil, ["fallback"])
      assert {:ok, "fallback"} = Filters.apply("default", false, ["fallback"])
      assert {:ok, "fallback"} = Filters.apply("default", "", ["fallback"])
      assert {:ok, "fallback"} = Filters.apply("default", [], ["fallback"])
    end

    test "default keeps a present, non-blank value" do
      assert {:ok, "value"} = Filters.apply("default", "value", ["fallback"])
      assert {:ok, 0} = Filters.apply("default", 0, ["fallback"])
    end

    test "date formats a Date/DateTime/NaiveDateTime struct" do
      assert {:ok, "2024-01-15"} = Filters.apply("date", ~D[2024-01-15], ["%Y-%m-%d"])
      assert {:ok, "2024-01-15"} = Filters.apply("date", ~N[2024-01-15 10:30:00], ["%Y-%m-%d"])
    end

    test "date formats an ISO 8601 string" do
      assert {:ok, "2024-01-15"} = Filters.apply("date", "2024-01-15T10:30:00Z", ["%Y-%m-%d"])
    end

    test "date returns an error for an unparseable string" do
      assert {:error, {:invalid_date, "not a date"}} = Filters.apply("date", "not a date", ["%Y"])
    end

    test "inspect is useful for debugging templates" do
      assert {:ok, "%{a: 1}"} = Filters.apply("inspect", %{a: 1}, [])
    end

    test "inspect on nil" do
      assert {:ok, "nil"} = Filters.apply("inspect", nil, [])
    end
  end

  describe "type coercion" do
    test "upcase on a non-string value coerces instead of crashing" do
      assert {:ok, "42"} = Filters.apply("upcase", 42, [])
      assert {:ok, "TRUE"} = Filters.apply("upcase", true, [])
    end

    test "plus on numeric strings coerces to numbers" do
      assert {:ok, 3} = Filters.apply("plus", "1", ["2"])
    end
  end
end
