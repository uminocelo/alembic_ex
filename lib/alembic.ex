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

  def compile!(source, options) do
    source
    |> compile(options)
    |> unwrap!(:compile)
  end

  def render!(compiled, assigns, options) do
    compiled
    |> render(assigns, options)
    |> unwrap!(:render)
  end

  defp unwrap!({:ok, result}, _operation), do: result

  defp unwrap!({:error, reason}, operation) do
    raise RuntimeError, "Alembic #{operation} failed: #{inspect(reason)}"
  end
end
