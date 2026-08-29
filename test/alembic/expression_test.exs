defmodule Alembic.Parser.ExpressionTest do
  use ExUnit.Case, async: true

  alias Alembic.Parser.Expression

  describe "variable paths" do
    test "dot notation" do
      assert {:ok, {:variable, ["a", "b", "c"]}} = Expression.parse("a.b.c")
    end

    test "bracket notation" do
      assert {:ok, {:variable, ["a", "b"]}} = Expression.parse(~s(a["b"]))
    end

    test "mixed dot and bracket notation" do
      assert {:ok, {:variable, ["posts", "0", "title"]}} = Expression.parse("posts[0].title")
    end

    test "dot and bracket notation are equivalent" do
      assert Expression.parse("user.name") == Expression.parse(~s(user["name"]))
    end

    test "disallows empty path segments" do
      assert {:error, {:unexpected_token, :expected_identifier_after_dot}} =
               Expression.parse("user..name")
    end
  end

  describe "literals" do
    test "string literals with double quotes" do
      assert {:ok, {:literal, "hello"}} = Expression.parse(~s("hello"))
    end

    test "string literals with single quotes" do
      assert {:ok, {:literal, "hello"}} = Expression.parse("'hello'")
    end

    test "integer literals" do
      assert {:ok, {:literal, 42}} = Expression.parse("42")
    end

    test "negative integer literals" do
      assert {:ok, {:literal, -3}} = Expression.parse("-3")
      assert {:ok, {:literal, 0}} = Expression.parse("-0")
    end

    test "float literals" do
      assert {:ok, {:literal, 3.14}} = Expression.parse("3.14")
    end

    test "boolean literals" do
      assert {:ok, {:literal, true}} = Expression.parse("true")
      assert {:ok, {:literal, false}} = Expression.parse("false")
    end

    test "nil literal and its alias" do
      assert {:ok, {:literal, nil}} = Expression.parse("nil")
      assert {:ok, {:literal, nil}} = Expression.parse("null")
    end

    test "empty string literal is distinct from nil" do
      assert {:ok, {:literal, ""}} = Expression.parse(~s(""))
    end
  end

  describe "comparison operators" do
    test "equality and inequality" do
      assert {:ok, {:compare, :eq, {:variable, ["x"]}, {:literal, 1}}} = Expression.parse("x == 1")
      assert {:ok, {:compare, :neq, {:variable, ["x"]}, {:literal, 1}}} = Expression.parse("x != 1")
    end

    test "relational operators" do
      assert {:ok, {:compare, :gt, {:variable, ["x"]}, {:literal, 0}}} = Expression.parse("x > 0")
      assert {:ok, {:compare, :lt, {:variable, ["x"]}, {:literal, 0}}} = Expression.parse("x < 0")
      assert {:ok, {:compare, :gte, {:variable, ["x"]}, {:literal, 0}}} = Expression.parse("x >= 0")
      assert {:ok, {:compare, :lte, {:variable, ["x"]}, {:literal, 0}}} = Expression.parse("x <= 0")
    end

    test "contains operator" do
      assert {:ok, {:compare, :contains, {:variable, ["s"]}, {:literal, "hello"}}} =
               Expression.parse(~s(s contains "hello"))
    end
  end

  describe "logical operators" do
    test "and / or as binary infix operators" do
      assert {:ok, {:logical, :and, {:variable, ["a"]}, {:variable, ["b"]}}} =
               Expression.parse("a and b")

      assert {:ok, {:logical, :or, {:variable, ["a"]}, {:variable, ["b"]}}} =
               Expression.parse("a or b")
    end

    test "not as a unary prefix operator" do
      assert {:ok, {:not, {:variable, ["x"]}}} = Expression.parse("not x")
    end

    test "chained and is left-associative" do
      assert {:ok, {:logical, :and, {:logical, :and, {:variable, ["a"]}, {:variable, ["b"]}}, {:variable, ["c"]}}} =
               Expression.parse("a and b and c")
    end

    test "precedence: not binds tighter than and, and binds tighter than or" do
      # Per docs/grammar.md section 5.4: not > and > or means or is the
      # outermost split, giving ((not a) and b) or c — NOT (not a) and (b or c).
      assert {:ok,
              {:logical, :or, {:logical, :and, {:not, {:variable, ["a"]}}, {:variable, ["b"]}},
               {:variable, ["c"]}}} = Expression.parse("not a and b or c")
    end

    test "comparisons combine with logical operators" do
      assert {:ok, {:logical, :and, {:compare, :gt, _, _}, _}} = Expression.parse("x > 0 and b")
    end
  end

  describe "filter chain" do
    test "filter with no arguments" do
      assert {:ok, {:filter_chain, {:variable, ["n"]}, [{:filter, "upcase", []}]}} =
               Expression.parse("n | upcase")
    end

    test "filter with a single argument" do
      assert {:ok, {:filter_chain, {:variable, ["name"]}, [{:filter, "truncate", [{:literal, 30}]}]}} =
               Expression.parse("name | truncate: 30")
    end

    test "filter with multiple arguments" do
      assert {:ok,
              {:filter_chain, {:variable, ["name"]},
               [{:filter, "slice", [{:literal, 0}, {:literal, 5}]}]}} =
               Expression.parse("name | slice: 0, 5")
    end

    test "chained filters collapse into a single filter_chain node" do
      assert {:ok,
              {:filter_chain, {:variable, ["name"]},
               [{:filter, "upcase", []}, {:filter, "truncate", [{:literal, 30}]}]}} =
               Expression.parse("name | upcase | truncate: 30")
    end

    test "filter arguments may be variables" do
      assert {:ok, {:filter_chain, _, [{:filter, "default", [{:variable, ["site", "title"]}]}]}} =
               Expression.parse("title | default: site.title")
    end

    test "bare variable with no filters is not wrapped" do
      assert {:ok, {:variable, ["name"]}} = Expression.parse("name")
    end
  end

  describe "error cases" do
    test "unterminated string literal" do
      assert {:error, :unterminated_string} = Expression.parse(~s("hello))
    end

    test "unknown operator" do
      assert {:error, {:unknown_operator, "**"}} = Expression.parse("x ** y")
    end

    test "empty expression" do
      assert {:error, :empty_expression} = Expression.parse("")
      assert {:error, :empty_expression} = Expression.parse("   ")
    end

    test "filter without a name" do
      assert {:error, :missing_filter_name} = Expression.parse("name | ")
    end
  end
end
