defmodule Alembic.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/uminocelo/alembic_ex"

  def project do
    [
      app: :alembic,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: elixirc_options(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    template engine
    """
  end

  defp package do
    [
      name: "alembic_template_engine",
      licenses: ["MIT"],
      links: %{
        "Github" => @source_url
      },
      files: [
        "lib",
        "LICENSE",
        "mix.exs",
        "README.md"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_url: "v#{@version}"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp elixirc_options(:test), do: [warnings_as_errors: true]
  defp elixirc_options(_env), do: []
end
