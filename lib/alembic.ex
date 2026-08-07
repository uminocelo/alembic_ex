defmodule Alembic do
  @moduledoc """
  Documentation for `Alembic`.
  """

  @type source :: String.t()
  @type template_path :: Path.t()
  @type assigns :: map()
  @type options :: keyword()
  @type compiled :: term()
  @type reason :: term()

  def compile(_source, _options) do
    {:error, :not_implemented}
  end

  def render(_compiled, _assigns, _options) do
    {:error, :not_implemented}
  end

  def render_file(_path, _assigns, _options) do
    {:error, :not_implemented}
  end

  def compile!(_source, _options) do
    raise RuntimeError, "Alembic compile failed: :not_implemented"
  end

  def render!(_compiled, _assigns, _options) do
    raise RuntimeError, "Alembic render failed: :not_implemented"
  end
end
