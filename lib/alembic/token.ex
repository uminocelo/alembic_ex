defmodule Alembic.Token do
  @moduledoc false

  @type t :: {:text, String.t()} | {:output, String.t()} | {:tag, String.t()}
end
