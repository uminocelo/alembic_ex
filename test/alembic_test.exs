defmodule AlembicTest do
  use ExUnit.Case
  doctest Alembic

  test "greets the world" do
    assert Alembic.hello() == :world
  end
end
