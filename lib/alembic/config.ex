defmodule Alembic.Config do
  @moduledoc """
  Reads and validates `:alembic` application configuration.

      # config/config.exs
      config :alembic,
        template_roots: ["priv/templates"],
        template_extensions: [".html", ".liquid"],
        cache: true,
        custom_filters: [],
        max_inheritance_depth: 10
  """

  require Logger

  @default_extensions [".html", ".liquid"]
  @default_max_inheritance_depth 10

  @doc """
  `config :alembic, :template_roots` — the directories `Alembic.Loader`
  searches, in order. Defaults to `[]`.

  ## Examples

      iex> Application.delete_env(:alembic, :template_roots)
      iex> Alembic.Config.template_roots()
      []
  """
  @spec template_roots() :: [String.t()]
  def template_roots, do: Application.get_env(:alembic, :template_roots, [])

  @doc """
  `config :alembic, :template_extensions` — extensions tried, in order,
  when a template name has none. Defaults to `[".html", ".liquid"]`.

  ## Examples

      iex> Application.delete_env(:alembic, :template_extensions)
      iex> Alembic.Config.template_extensions()
      [".html", ".liquid"]
  """
  @spec template_extensions() :: [String.t()]
  def template_extensions,
    do: Application.get_env(:alembic, :template_extensions, @default_extensions)

  @doc """
  `config :alembic, :cache` — whether `Alembic.Cache` is active. Defaults
  to `true`.

  ## Examples

      iex> Application.delete_env(:alembic, :cache)
      iex> Alembic.Config.cache_enabled?()
      true
  """
  @spec cache_enabled?() :: boolean()
  def cache_enabled?, do: Application.get_env(:alembic, :cache, true)

  @doc """
  `config :alembic, :custom_filters` — modules implementing
  `Alembic.Filter`, checked before the built-in catalog. Defaults to `[]`.

  ## Examples

      iex> Application.delete_env(:alembic, :custom_filters)
      iex> Alembic.Config.custom_filters()
      []
  """
  @spec custom_filters() :: [module()]
  def custom_filters, do: Application.get_env(:alembic, :custom_filters, [])

  @doc """
  `config :alembic, :max_inheritance_depth` — the maximum `{% extends %}`
  chain length before `Alembic.Inheritance.resolve_chain/3` returns
  `{:error, :inheritance_depth_exceeded}`. Defaults to `10`.

  ## Examples

      iex> Application.delete_env(:alembic, :max_inheritance_depth)
      iex> Alembic.Config.max_inheritance_depth()
      10
  """
  @spec max_inheritance_depth() :: pos_integer()
  def max_inheritance_depth,
    do: Application.get_env(:alembic, :max_inheritance_depth, @default_max_inheritance_depth)

  @doc """
  Validates configuration at application start. Currently just warns when
  `:template_roots` is empty, since that means `render_file/3` can never
  find a template — a common misconfiguration, not a hard error (an
  application that only ever calls `render_string/3` has no use for it).

  ## Examples

      iex> Alembic.Config.validate!()
      :ok
  """
  @spec validate!() :: :ok
  def validate! do
    if template_roots() == [] do
      Logger.warning(
        "Alembic: :template_roots is not configured — render_file/3 will never find a " <>
          "template. Set it via `config :alembic, template_roots: [\"priv/templates\"]`."
      )
    end

    :ok
  end
end
