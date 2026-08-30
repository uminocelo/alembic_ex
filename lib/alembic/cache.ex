defmodule Alembic.Cache do
  @moduledoc """
  OTP GenServer owning a `:public` ETS table used as a compiled-template
  cache, keyed by `{path, mtime}`. A cache hit skips the tokenize → parse
  pipeline entirely; a modified source file (different mtime) is a
  different key, so it is automatically a miss.

  `get/1` reads ETS directly (`:ets.lookup/2`) — it never goes through the
  GenServer mailbox, so concurrent readers are never serialized against
  each other. `put/2`, `invalidate/1`, and `clear/0` are casts, serialized
  through the GenServer as the single writer, giving mutual exclusion on
  writes without locks. `sweep/0` is a call (it needs to return a count).

  This is the project's first real OTP module — GenServer as an actor with
  a mailbox (casts/calls are serialized through the process automatically),
  ETS as shared memory (reads bypass the mailbox for concurrency, writes go
  through the GenServer for safety), and supervision as fault tolerance
  (the `one_for_one` supervisor in `Alembic.Application` restarts this
  GenServer — and therefore recreates its ETS table — if it crashes).

  ## Deviation from issue 1.5.2: no `:telemetry` dependency

  The issue's task list calls for `:telemetry.execute/3` on hit/miss.
  `:telemetry` is a separate Hex package, and issue 1.1.1 established a
  hard zero-runtime-dependencies policy (`ex_doc` only, dev-only). Adding a
  telemetry dependency here would violate that project-wide constraint set
  two milestones earlier. `Logger.debug/1` calls with the same
  `path`/hit-or-miss information stand in for the telemetry events instead
  — observable, but without the extra dependency.

  Each call passes a zero-arity function (`Logger.debug(fn -> ... end)`),
  not a plain string, so the `"Alembic.Cache hit: \#{path}"` interpolation
  only runs when the configured Logger level would actually emit it.
  `do_get/1` is the hottest path in the module — this matters there more
  than the write paths below, which are already off the direct read path
  entirely.
  """

  use GenServer

  require Logger

  @table :alembic_template_cache

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Whether the cache is enabled (`config :alembic, :cache`, default `true`).
  Every other public function in this module is a no-op when this is `false`.

  ## Examples

      iex> Alembic.Cache.enabled?()
      true
  """
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:alembic, :cache, true)

  @doc """
  Looks up a compiled AST by its resolved path and current mtime. Reads
  ETS directly (`:ets.lookup/2`) — never goes through the GenServer
  mailbox, so concurrent readers are never serialized against each other.

  ## Examples

      iex> path = Path.join(System.tmp_dir!(), "alembic_cache_doctest.html")
      iex> File.write!(path, "content")
      iex> Alembic.Cache.invalidate(path)
      iex> Alembic.Cache.sweep()
      iex> Alembic.Cache.get(path)
      :miss

      iex> path = Path.join(System.tmp_dir!(), "alembic_cache_doctest_hit.html")
      iex> File.write!(path, "content")
      iex> Alembic.Cache.put(path, [{:text, "hello"}])
      iex> Alembic.Cache.sweep()
      iex> Alembic.Cache.get(path)
      {:hit, [{:text, "hello"}]}
  """
  @spec get(String.t()) :: {:hit, term()} | :miss
  def get(path) do
    if enabled?() do
      do_get(path)
    else
      :miss
    end
  end

  @doc """
  Stores a compiled AST under `{path, current_mtime}`. A write, so it goes
  through the GenServer as a cast (serializing mutation); use `sweep/0`
  (a call, sharing the same FIFO mailbox as casts) to wait for a prior
  `put/2` to be processed before a synchronous `get/1`.

  ## Examples

      iex> path = Path.join(System.tmp_dir!(), "alembic_cache_doctest.html")
      iex> Alembic.Cache.put(path, [{:text, "hello"}])
      :ok
  """
  @spec put(String.t(), term()) :: :ok
  def put(path, ast) do
    if enabled?(), do: GenServer.cast(__MODULE__, {:put, path, ast})
    :ok
  end

  @doc """
  Removes every cached entry for `path`, regardless of the mtime they were
  stored under.

  ## Examples

      iex> path = Path.join(System.tmp_dir!(), "alembic_cache_doctest.html")
      iex> Alembic.Cache.put(path, [{:text, "hello"}])
      iex> Alembic.Cache.invalidate(path)
      iex> Alembic.Cache.sweep()
      iex> Alembic.Cache.get(path)
      :miss
  """
  @spec invalidate(String.t()) :: :ok
  def invalidate(path) do
    if enabled?(), do: GenServer.cast(__MODULE__, {:invalidate, path})
    :ok
  end

  @doc """
  Removes every entry in the cache.

  ## Examples

      iex> path = Path.join(System.tmp_dir!(), "alembic_cache_doctest.html")
      iex> Alembic.Cache.put(path, [{:text, "hello"}])
      iex> Alembic.Cache.clear()
      iex> Alembic.Cache.sweep()
      iex> Alembic.Cache.get(path)
      :miss
  """
  @spec clear() :: :ok
  def clear do
    if enabled?(), do: GenServer.cast(__MODULE__, :clear)
    :ok
  end

  @doc """
  Removes entries whose source file no longer exists or has a different
  mtime than when it was cached. Returns the count removed.

  ## Examples

      iex> path = Path.join(System.tmp_dir!(), "alembic_cache_doctest_sweep.html")
      iex> File.write!(path, "content")
      iex> Alembic.Cache.put(path, [{:text, "hello"}])
      iex> Alembic.Cache.sweep()
      iex> File.rm!(path)
      iex> {:ok, removed} = Alembic.Cache.sweep()
      iex> removed >= 1
      true
  """
  @spec sweep() :: {:ok, non_neg_integer()}
  def sweep do
    if enabled?(), do: GenServer.call(__MODULE__, :sweep), else: {:ok, 0}
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:put, path, ast}, state) do
    case current_mtime(path) do
      {:ok, mtime} -> :ets.insert(@table, {{path, mtime}, ast})
      :error -> :ok
    end

    {:noreply, state}
  end

  def handle_cast({:invalidate, path}, state) do
    :ets.match_delete(@table, {{path, :_}, :_})
    {:noreply, state}
  end

  def handle_cast(:clear, state) do
    :ets.delete_all_objects(@table)
    {:noreply, state}
  end

  @impl true
  def handle_call(:sweep, _from, state) do
    {:reply, {:ok, sweep_table()}, state}
  end

  defp do_get(path) do
    case current_mtime(path) do
      {:ok, mtime} -> lookup_and_log(path, mtime)
      :error -> :miss
    end
  end

  defp lookup_and_log(path, mtime) do
    case :ets.lookup(@table, {path, mtime}) do
      [{_key, ast}] ->
        Logger.debug(fn -> "Alembic.Cache hit: #{path}" end)
        {:hit, ast}

      [] ->
        Logger.debug(fn -> "Alembic.Cache miss: #{path}" end)
        :miss
    end
  end

  defp sweep_table do
    @table
    |> :ets.tab2list()
    |> Enum.reduce(0, fn {{path, mtime}, _ast} = entry, count ->
      if stale?(path, mtime) do
        :ets.delete_object(@table, entry)
        count + 1
      else
        count
      end
    end)
  end

  defp stale?(path, mtime) do
    case current_mtime(path) do
      {:ok, ^mtime} -> false
      _other -> true
    end
  end

  defp current_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> {:ok, mtime}
      {:error, _reason} -> :error
    end
  end
end
