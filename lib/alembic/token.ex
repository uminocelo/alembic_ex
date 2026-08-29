defmodule Alembic.Token do
  @moduledoc false

  @type t ::
          {:text, String.t()}
          | {:output, String.t(), boolean(), boolean()}
          | {:tag, String.t(), boolean(), boolean()}
end
