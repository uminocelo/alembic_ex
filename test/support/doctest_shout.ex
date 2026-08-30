defmodule Alembic.DocTest.Shout do
  @moduledoc false
  @behaviour Alembic.Filter

  @impl true
  def name, do: "shout"

  @impl true
  # credo:disable-for-next-line Credo.Check.Refactor.Apply
  def apply(value, []), do: {:ok, String.upcase(value) <> "!"}
end
