defmodule Alembic.Application do
  @moduledoc """
  OTP application callback module. Validates configuration
  (`Alembic.Config.validate!/0`) and starts a `one_for_one` supervisor
  whose only child is `Alembic.Cache` — the cache's ETS table is owned by
  that GenServer, so this supervisor is what recreates it if the cache
  process ever crashes.
  """

  use Application

  @impl true
  def start(_type, _args) do
    Alembic.Config.validate!()
    children = [Alembic.Cache]
    Supervisor.start_link(children, strategy: :one_for_one, name: Alembic.Supervisor)
  end
end
