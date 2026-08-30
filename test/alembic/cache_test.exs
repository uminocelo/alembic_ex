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

  describe "supervisor restart" do
    test "restarting the GenServer recreates the ETS table with a clean cache", %{path: path} do
      original_pid = Process.whereis(Cache)
      ref = Process.monitor(original_pid)

      Cache.put(path, [{:text, "before crash"}])
      wait_for_cast()
      assert {:hit, _ast} = Cache.get(path)

      Process.exit(original_pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^original_pid, :killed}

      wait_for_cache_restart()

      restarted_pid = Process.whereis(Cache)
      assert is_pid(restarted_pid)
      assert restarted_pid != original_pid

      # The old ETS table died with the old process — a fresh, empty one
      # was created by the new process's init/1, so the pre-crash entry
      # is gone even though the file on disk (and its mtime) is unchanged.
      assert :miss = Cache.get(path)

      # The restarted GenServer is fully functional.
      Cache.put(path, [{:text, "after restart"}])
      wait_for_cast()
      assert {:hit, [{:text, "after restart"}]} = Cache.get(path)
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

  # The supervisor's restarted child re-registers its name before init/1
  # (which creates the ETS table) has necessarily finished, so polling
  # Process.whereis/1 alone could observe a live pid backed by no table
  # yet. A synchronous call is only handled once init/1 has returned, so
  # retrying `sweep/0` until it succeeds guarantees the table exists.
  defp wait_for_cache_restart(attempts \\ 50)

  defp wait_for_cache_restart(0), do: flunk("Alembic.Cache did not restart in time")

  defp wait_for_cache_restart(attempts) do
    Alembic.Cache.sweep()
  catch
    :exit, _reason ->
      Process.sleep(10)
      wait_for_cache_restart(attempts - 1)
  end
end
