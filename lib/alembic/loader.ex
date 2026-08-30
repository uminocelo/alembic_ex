defmodule Alembic.Loader do
  @moduledoc """
  Resolves template names to files across one or more configured template
  root directories and reads their contents. Supports multiple roots
  (checked in order, first match wins), automatic extension appending when
  a template name has none, and path-traversal protection.

  `File.read/1` (and `File.stat/2`) are called directly on each candidate
  path — never `File.exists?/1` first. Checking existence and then reading
  is a TOCTOU race; attempting the read/stat and handling its error is the
  correct approach.
  """

  require Logger

  @type reason ::
          {:template_not_found, [String.t()]}
          | {:path_traversal_detected, String.t()}

  @default_extensions [".html", ".liquid"]

  @doc """
  Reads a template's content by name, walking `opts[:roots]` (or
  `config :alembic, :template_roots`) in order.

  ## Examples

      iex> {:ok, content} = Alembic.Loader.load("base.html", roots: ["test/fixtures/templates"])
      iex> content =~ "Alembic"
      true

      iex> {:error, {:template_not_found, paths}} = Alembic.Loader.load("nope.html", roots: ["test/fixtures/templates"])
      iex> Enum.any?(paths, &String.ends_with?(&1, "nope.html"))
      true
  """
  @spec load(String.t(), keyword()) :: {:ok, String.t()} | {:error, reason()}
  def load(name, opts \\ []) do
    case resolve(roots(opts), extensions(opts), name, &File.read/1) do
      {:ok, content} ->
        {:ok, content}

      {:error, {:template_not_found, _searched} = reason} ->
        Logger.warning("Alembic template not found: #{inspect(name)}")
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Builds a `(name -> {:ok, source} | {:error, reason})` function capturing
  `opts` — used for dependency injection into
  `Alembic.Inheritance.resolve_chain/3`.

  ## Examples

      iex> loader = Alembic.Loader.build_loader(roots: ["test/fixtures/templates"])
      iex> {:ok, content} = loader.("base.html")
      iex> content =~ "Alembic"
      true
  """
  @spec build_loader(keyword()) :: (String.t() -> {:ok, String.t()} | {:error, reason()})
  def build_loader(opts \\ []), do: fn name -> load(name, opts) end

  @doc """
  Returns the mtime of a resolved template — used by `Alembic.Cache` to
  detect a stale entry.

  ## Examples

      iex> {:ok, mtime} = Alembic.Loader.stat("base.html", roots: ["test/fixtures/templates"])
      iex> match?(%DateTime{}, mtime)
      true
  """
  @spec stat(String.t(), keyword()) :: {:ok, DateTime.t()} | {:error, reason() | File.posix()}
  def stat(name, opts \\ []) do
    resolve(roots(opts), extensions(opts), name, &stat_mtime/1)
  end

  @doc """
  Resolves `name` to an absolute path across the configured roots, without
  reading its content. Added beyond issue 1.5.1's own public API: the
  top-level pipeline (`Alembic.render_file/3`, issue 1.5.3) needs the fully
  resolved path — not just its content — to use as `Alembic.Cache`'s cache
  key, since the cache is keyed by a real, statable filesystem path, not a
  root-relative template name.

  ## Examples

      iex> {:ok, path} = Alembic.Loader.resolve_path("base.html", roots: ["test/fixtures/templates"])
      iex> Path.type(path)
      :absolute
  """
  @spec resolve_path(String.t(), keyword()) :: {:ok, String.t()} | {:error, reason()}
  def resolve_path(name, opts \\ []) do
    resolve(roots(opts), extensions(opts), name, fn path ->
      if File.regular?(path), do: {:ok, path}, else: {:error, :enoent}
    end)
  end

  defp roots(opts) do
    Keyword.get(opts, :roots, Application.get_env(:alembic, :template_roots, []))
  end

  defp extensions(opts) do
    Keyword.get(
      opts,
      :extensions,
      Application.get_env(:alembic, :template_extensions, @default_extensions)
    )
  end

  defp resolve(roots, extensions, name, attempt_fn) do
    roots
    |> candidates(extensions, name)
    |> Enum.reduce_while({:not_found, []}, &try_candidate(&1, &2, attempt_fn))
    |> case do
      {:found, result} -> {:ok, result}
      {:not_found, searched} -> {:error, {:template_not_found, Enum.reverse(searched)}}
      {:traversal, path} -> {:error, {:path_traversal_detected, path}}
    end
  end

  defp try_candidate({root, candidate}, {:not_found, searched}, attempt_fn) do
    case safe_path(root, candidate) do
      {:ok, expanded} -> try_attempt(attempt_fn, expanded, searched)
      {:error, unsafe_path} -> {:halt, {:traversal, unsafe_path}}
    end
  end

  defp try_attempt(attempt_fn, expanded, searched) do
    case attempt_fn.(expanded) do
      {:ok, result} -> {:halt, {:found, result}}
      {:error, _posix} -> {:cont, {:not_found, [expanded | searched]}}
    end
  end

  defp candidates(roots, extensions, name) do
    Enum.flat_map(roots, fn root ->
      Enum.map(candidate_names(extensions, name), &{root, Path.join(root, &1)})
    end)
  end

  defp candidate_names(extensions, name) do
    if Path.extname(name) == "" do
      Enum.map(extensions, &(name <> &1))
    else
      [name]
    end
  end

  defp safe_path(root, candidate) do
    expanded_root = Path.expand(root)
    expanded_candidate = Path.expand(candidate)

    if String.starts_with?(expanded_candidate, expanded_root) do
      {:ok, expanded_candidate}
    else
      {:error, expanded_candidate}
    end
  end

  defp stat_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> {:ok, DateTime.from_unix!(mtime)}
      {:error, reason} -> {:error, reason}
    end
  end
end
