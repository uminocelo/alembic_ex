defmodule Alembic.ConfigTest do
  use ExUnit.Case

  doctest Alembic.Config

  alias Alembic.Config

  describe "defaults" do
    test "template_roots defaults to an empty list when unset" do
      Application.delete_env(:alembic, :template_roots)
      assert Config.template_roots() == []
    end

    test "template_extensions defaults to html and liquid" do
      Application.delete_env(:alembic, :template_extensions)
      assert Config.template_extensions() == [".html", ".liquid"]
    end

    test "cache_enabled? defaults to true" do
      Application.delete_env(:alembic, :cache)
      assert Config.cache_enabled?() == true
    end

    test "custom_filters defaults to an empty list" do
      Application.delete_env(:alembic, :custom_filters)
      assert Config.custom_filters() == []
    end

    test "max_inheritance_depth defaults to 10" do
      Application.delete_env(:alembic, :max_inheritance_depth)
      assert Config.max_inheritance_depth() == 10
    end
  end

  describe "reading configured values" do
    test "each getter reflects Application config" do
      Application.put_env(:alembic, :template_roots, ["priv/templates"])
      Application.put_env(:alembic, :template_extensions, [".liquid"])
      Application.put_env(:alembic, :cache, false)
      Application.put_env(:alembic, :custom_filters, [__MODULE__])
      Application.put_env(:alembic, :max_inheritance_depth, 3)

      assert Config.template_roots() == ["priv/templates"]
      assert Config.template_extensions() == [".liquid"]
      assert Config.cache_enabled?() == false
      assert Config.custom_filters() == [__MODULE__]
      assert Config.max_inheritance_depth() == 3
    after
      Application.delete_env(:alembic, :template_roots)
      Application.delete_env(:alembic, :template_extensions)
      Application.delete_env(:alembic, :cache)
      Application.delete_env(:alembic, :custom_filters)
      Application.delete_env(:alembic, :max_inheritance_depth)
    end
  end

  describe "validate!/0" do
    test "returns :ok whether or not template_roots is configured" do
      Application.delete_env(:alembic, :template_roots)
      assert :ok = Config.validate!()

      Application.put_env(:alembic, :template_roots, ["priv/templates"])
      assert :ok = Config.validate!()
    after
      Application.delete_env(:alembic, :template_roots)
    end
  end
end
