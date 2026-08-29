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
      extra_applications: [:logger],
      mod: {Alembic.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  defp description do
    "A Liquid-compatible template engine for Elixir, with zero runtime dependencies."
  end

  defp package do
    [
      name: "alembic_template_engine",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: [
        "lib",
        "docs/grammar.md",
        "LICENSE",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "COMPATIBILITY.md"
      ]
    ]
  end

  defp docs do
    [
      main: "Alembic",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "docs/grammar.md": [title: "Template Grammar"],
        "COMPATIBILITY.md": [title: "Liquid Compatibility"],
        "BENCHMARKS.md": [title: "Benchmarks"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ],
      groups_for_modules: [
        Pipeline: [
          Alembic.Lexer,
          Alembic.Token,
          Alembic.Parser,
          Alembic.Parser.Expression,
          Alembic.AST,
          Alembic.Evaluator
        ],
        Runtime: [
          Alembic.Context,
          Alembic.Filters,
          Alembic.Filter,
          Alembic.Inheritance
        ],
        Infrastructure: [
          Alembic.Loader,
          Alembic.Cache,
          Alembic.Config,
          Alembic.Application
        ],
        Errors: [
          Alembic.TemplateError,
          Alembic.CompileError,
          Alembic.RenderError
        ]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp elixirc_options(:test), do: [warnings_as_errors: true]
  defp elixirc_options(_env), do: []
end
