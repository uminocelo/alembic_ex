defmodule Alembic.ContextTest do
  use ExUnit.Case, async: true

  doctest Alembic.Context

  alias Alembic.Context

  describe "construction" do
    test "new/1 creates a context with one root scope" do
      ctx = Context.new(%{"name" => "Alice"})
      assert %Context{scopes: [%{"name" => "Alice"}], assigns: %{}} = ctx
    end
  end

  describe "lookup/2" do
    test "finds a value in the root scope" do
      ctx = Context.new(%{"name" => "Alice"})
      assert {:ok, "Alice"} = Context.lookup(ctx, "name")
    end

    test "returns :not_found for a missing key" do
      ctx = Context.new(%{"name" => "Alice"})
      assert :not_found = Context.lookup(ctx, "missing")
    end

    test "transparently matches atom keys for a string lookup" do
      ctx = Context.new(%{name: "Alice"})
      assert {:ok, "Alice"} = Context.lookup(ctx, "name")
    end

    test "falls back to assigns after all scopes" do
      ctx = Context.new(%{}) |> Context.assign("count", 10)
      assert {:ok, 10} = Context.lookup(ctx, "count")
    end

    test "a scoped variable shadows an assign of the same name" do
      ctx =
        Context.new(%{})
        |> Context.assign("name", "assigned")
        |> Context.push_scope(%{"name" => "scoped"})

      assert {:ok, "scoped"} = Context.lookup(ctx, "name")
    end
  end

  describe "push_scope/2 and pop_scope/1" do
    test "inner scope shadows outer scope" do
      ctx = Context.new(%{"name" => "Alice"}) |> Context.push_scope(%{"name" => "Bob"})
      assert {:ok, "Bob"} = Context.lookup(ctx, "name")
    end

    test "pop_scope restores the outer value (round-trip)" do
      ctx = Context.new(%{"name" => "Alice"})
      pushed = Context.push_scope(ctx, %{"name" => "Bob"})
      popped = Context.pop_scope(pushed)

      assert {:ok, "Alice"} = Context.lookup(popped, "name")
      assert popped == ctx
    end

    test "pop_scope on the root scope raises" do
      ctx = Context.new(%{})
      assert_raise ArgumentError, fn -> Context.pop_scope(ctx) end
    end

    test "push_scope does not mutate the original context" do
      ctx = Context.new(%{"name" => "Alice"})
      _pushed = Context.push_scope(ctx, %{"name" => "Bob"})
      assert {:ok, "Alice"} = Context.lookup(ctx, "name")
    end
  end

  describe "resolve_path/2" do
    test "resolves a nested map path" do
      ctx = Context.new(%{"user" => %{"address" => %{"city" => "Lisbon"}}})
      assert {:ok, "Lisbon"} = Context.resolve_path(ctx, ["user", "address", "city"])
    end

    test "resolves atom-keyed nested maps via string path segments" do
      ctx = Context.new(%{"user" => %{name: "Alice"}})
      assert {:ok, "Alice"} = Context.resolve_path(ctx, ["user", "name"])
    end

    test "resolves a list index" do
      ctx = Context.new(%{"posts" => ["a", "b", "c"]})
      assert {:ok, "b"} = Context.resolve_path(ctx, ["posts", "1"])
    end

    test "out-of-bounds list index is :not_found, not {:ok, nil}" do
      ctx = Context.new(%{"posts" => ["a", "b", "c"]})
      assert :not_found = Context.resolve_path(ctx, ["posts", "10"])
    end

    test "resolves a keyword list" do
      ctx = Context.new(%{"opts" => [title: "Hello"]})
      assert {:ok, "Hello"} = Context.resolve_path(ctx, ["opts", "title"])
    end

    test "path through a missing root key is :not_found" do
      ctx = Context.new(%{})
      assert :not_found = Context.resolve_path(ctx, ["missing", "nested"])
    end

    test "path segment on a non-traversable value is :not_found" do
      ctx = Context.new(%{"name" => "Alice"})
      assert :not_found = Context.resolve_path(ctx, ["name", "nested"])
    end

    test "single-segment path is equivalent to lookup" do
      ctx = Context.new(%{"name" => "Alice"})
      assert {:ok, "Alice"} = Context.resolve_path(ctx, ["name"])
    end
  end

  describe "assign/3" do
    test "persists across push_scope / pop_scope cycles" do
      ctx =
        Context.new(%{})
        |> Context.assign("count", 10)
        |> Context.push_scope(%{"item" => "x"})

      assert {:ok, 10} = Context.lookup(ctx, "count")

      ctx = Context.pop_scope(ctx)
      assert {:ok, 10} = Context.lookup(ctx, "count")
    end

    test "later assign overwrites an earlier one" do
      ctx = Context.new(%{}) |> Context.assign("x", 1) |> Context.assign("x", 2)
      assert {:ok, 2} = Context.lookup(ctx, "x")
    end
  end

  describe "forloop_meta/3" do
    test "first iteration" do
      meta = Context.forloop_meta(0, 3, "a")

      assert meta == %{
               "forloop" => %{
                 "index" => 1,
                 "index0" => 0,
                 "rindex" => 3,
                 "rindex0" => 2,
                 "first" => true,
                 "last" => false,
                 "length" => 3
               }
             }
    end

    test "middle iteration" do
      meta = Context.forloop_meta(1, 3, "b")

      assert meta == %{
               "forloop" => %{
                 "index" => 2,
                 "index0" => 1,
                 "rindex" => 2,
                 "rindex0" => 1,
                 "first" => false,
                 "last" => false,
                 "length" => 3
               }
             }
    end

    test "last iteration" do
      meta = Context.forloop_meta(2, 3, "c")

      assert meta == %{
               "forloop" => %{
                 "index" => 3,
                 "index0" => 2,
                 "rindex" => 1,
                 "rindex0" => 0,
                 "first" => false,
                 "last" => true,
                 "length" => 3
               }
             }
    end
  end
end
