defmodule Alembic.Filter do
  @moduledoc """
  Behaviour for custom Alembic filters.

  Register custom filter modules via application config:

      config :alembic, :custom_filters, [MyApp.Filters.Money]

  Each module implements both callbacks: `name/0` is the filter name as
  invoked in templates (`{{ value | my_filter }}`), and `apply/2` performs
  the transformation. `name/0` is a small addition beyond what the issue's
  own sketch showed (just `apply/2`) — without it, a list of modules alone
  gives `Alembic.Filters` no way to map a template's filter name string back
  to the module that should handle it.
  """

  @doc "The filter name as it appears in a template's pipe chain, e.g. `\"money\"` for `{{ price | money }}`."
  @callback name() :: String.t()

  @doc "Transforms `value` given the filter's (already-evaluated) `args`."
  @callback apply(value :: any(), args :: [any()]) :: {:ok, any()} | {:error, reason :: any()}
end
