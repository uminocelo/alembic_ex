defmodule Alembic.TestFixtures do
  @moduledoc false

  def plain_template do
    "Hello from Alembic!"
  end

  def multiline_template do
    """
    First line
    Second line
    """
  end

  def empty_assigns do
    %{}
  end
end
