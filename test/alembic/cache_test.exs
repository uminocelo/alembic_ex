defmodule Alembic.CacheTest do
  # Alembic.Cache is a single named GenServer shared process-wide — its
  # tests must not run concurrently with each other or they'll race on the
  # same ETS table.
  use ExUnit.Case, async: false

  doctest Alembic.Cache

  alias Alembic.Cache

  @tmp_dir "test/fixtures/tmp"

  setup do
    Application.delete_env(:alembic, :cache)
    File.mkdir_p!(@tmp_dir)
    # A unique path per test means no test needs a globally empty cache to
    # start from — deliberately not calling Cache.clear() here, since
    # Alembic.Cache is a single process-wide GenServer and a blanket clear
    # would nuke any other test file's cache entries too (clear/0 itself is
    # still exercised as its own explicit test, below).
    path = Path.join(@tmp_dir, "#{System.unique_integer([:positive])}.html")
    File.write!(path, "content")

    on_exit(fn -> File.rm(path) end)

    %{path: path}
  end

  describe "get/1 and put/2" do
    test "cache miss on first access", %{path: path} do
      assert :miss = Cache.get(path)
    end

    test "cache hit after put", %{path: path} do
      ast = [{:text, "hello"}]
      Cache.put(path, ast)
      wait_for_cast()
      assert {:hit, ^ast} = Cache.get(path)
    end

    test "a modified file (different mtime) is a cache miss", %{path: path} do
      ast = [{:text, "hello"}]
      Cache.put(path, ast)
      wait_for_cast()
      assert {:hit, ^ast} = Cache.get(path)

      # Force a different mtime.
      File.touch!(path, System.os_time(:second) + 120)

      assert :miss = Cache.get(path)
    end
  end

  describe "invalidate/1" do
    test "removes the entry for a path", %{path: path} do
      Cache.put(path, [{:text, "x"}])
      wait_for_cast()
      Cache.invalidate(path)
      wait_for_cast()
      assert :miss = Cache.get(path)
    end
  end

  describe "clear/0" do
    test "removes all entries", %{path: path} do
      other_path = Path.join(@tmp_dir, "#{System.unique_integer([:positive])}.html")
      File.write!(other_path, "content")

      Cache.put(path, [{:text, "a"}])
      Cache.put(other_path, [{:text, "b"}])
      wait_for_cast()

      Cache.clear()
      wait_for_cast()

      assert :miss = Cache.get(path)
      assert :miss = Cache.get(other_path)
      File.rm(other_path)
    end
  end

  describe "sweep/0" do
    test "removes entries for files that no longer exist", %{path: path} do
      Cache.put(path, [{:text, "x"}])
      wait_for_cast()

      File.rm!(path)
      assert {:ok, removed} = Cache.sweep()
      assert removed >= 1
      assert :miss = Cache.get(path)
    end

    test "returns 0 when nothing is stale", %{path: path} do
      Cache.put(path, [{:text, "x"}])
      wait_for_cast()
      assert {:ok, 0} = Cache.sweep()
    end
  end

  describe "disabled cache" do
    test "all operations are no-ops", %{path: path} do
      Application.put_env(:alembic, :cache, false)

      Cache.put(path, [{:text, "x"}])
      assert :miss = Cache.get(path)
      assert :ok = Cache.invalidate(path)
      assert :ok = Cache.clear()
      assert {:ok, 0} = Cache.sweep()
    after
      # :alembic/:cache is global Application env, persisting for the whole
      # `mix test` BEAM process — leaving it disabled here would silently
      # break every cache-hit assertion in every OTHER test file that
      # happens to run afterward, depending on random test order.
      Application.delete_env(:alembic, :cache)
    end
  end

  describe "concurrent reads" do
    test "many concurrent readers all succeed without going through the GenServer", %{path: path} do
      ast = [{:text, "concurrent"}]
      Cache.put(path, ast)
      wait_for_cast()

      results =
        1..50
        |> Enum.map(fn _ -> Task.async(fn -> Cache.get(path) end) end)
        |> Enum.map(&Task.await/1)

      assert Enum.all?(results, &(&1 == {:hit, ast}))
    end
  end

  # Cache.put/invalidate/clear are casts, processed asynchronously. A call
  # (sweep/0) shares the same FIFO mailbox as casts — unlike :sys.get_state,
  # which uses OTP's out-of-band system-message protocol and does NOT
  # guarantee prior casts have been processed — so waiting for a call's
  # reply guarantees every earlier cast from this process was handled first.
  defp wait_for_cast, do: Alembic.Cache.sweep()
end
