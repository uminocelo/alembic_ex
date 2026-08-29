defmodule Alembic do
  @moduledoc """
  Alembic — a Liquid-compatible template engine for Elixir, with zero
  runtime dependencies.

  ## Quick start

      iex> {:ok, ast} = Alembic.compile("Hello {{ name }}!")
      iex> Alembic.render(ast, %{"name" => "World"})
      {:ok, "Hello World!"}

      iex> Alembic.render_string("Hi {{ user }}", %{"user" => "Alice"})
      {:ok, "Hi Alice"}

  ## The pipeline

      render_file(path, assigns, opts)
          │
          ├─ Loader.resolve_path(path, opts)      →  {:ok, resolved_path}
          │
          ├─ Cache.get(resolved_path)              →  {:hit, ast}  ───────┐
          │                                                               │
          └─ :miss                                                       │
              │                                                          │
              ├─ File.read(resolved_path)          →  {:ok, source}     │
              ├─ compile(source)                    →  {:ok, ast}       │
              ├─ Cache.put(resolved_path, ast)                           │
              └──────────────────────────────────────────────────────────┘
                      │
                      ├─ Inheritance.preprocess(ast, loader_fn) → {:ok, resolved_ast}
                      │
                      └─ Evaluator.eval(resolved_ast, Context.new(assigns)) → {:ok, html}

  `compile/2` and `render/3` are kept separate so a caller (e.g. Grimoire)
  can compile once and render many times — the same reason `render_file/3`
  bothers with a cache at all.

  ## Options

  | Option | Type | Default | Description |
  |---|---|---|---|
  | `:roots` | `[String.t()]` | `Alembic.Config.template_roots/0` | Override template root dirs |
  | `:extensions` | `[String.t()]` | `[".html", ".liquid"]` | File extensions tried when a name has none |
  | `:cache` | `boolean()` | `true` | Enable/disable the compiled-AST cache for this call |
  | `:strict` | `boolean()` | `false` | Error on undefined variables instead of rendering `""` |

  Custom filters are registered globally via
  `config :alembic, custom_filters: [MyApp.Filters.Money]` (see
  `Alembic.Filter`) — there is currently no per-call override for that one.

  ## Errors

  Every non-bang function returns `{:ok, value} | {:error, reason}`. Bang
  (`!`) variants raise `Alembic.TemplateError` — see that module and
  `Alembic.CompileError` / `Alembic.RenderError` below.
  """

  alias Alembic.{AST, Cache, Context, Evaluator, Inheritance, Lexer, Loader, Parser}

  @type compile_error :: {:lexer, Lexer.reason()} | {:parser, Parser.reason()}
  @type render_error ::
          {:inheritance, Inheritance.reason()}
          | {:evaluator, Evaluator.reason()}
          | {:loader, Loader.reason() | File.posix()}

  @doc """
  Compiles a template source string into an AST.

  ## Examples

      iex> {:ok, ast} = Alembic.compile("Hello {{ name }}!")
      iex> ast
      [{:text, "Hello "}, {:output, ["name"], []}, {:text, "!"}]

      iex> Alembic.compile("{{ }}")
      {:error, {:lexer, {:empty_output_tag, %{line: 1, col: 1}}}}
  """
  @spec compile(String.t(), keyword()) :: {:ok, AST.t()} | {:error, compile_error()}
  def compile(source, _opts \\ []) when is_binary(source) do
    with {:ok, tokens} <- lexer_step(source) do
      parser_step(tokens)
    end
  end

  @doc """
  Compiles a template source string into an AST, raising on error.

  ## Examples

      iex> Alembic.compile!("Hello {{ name }}!")
      [{:text, "Hello "}, {:output, ["name"], []}, {:text, "!"}]
  """
  @spec compile!(String.t(), keyword()) :: AST.t()
  def compile!(source, opts \\ []) do
    case compile(source, opts) do
      {:ok, ast} -> ast
      {:error, reason} -> raise Alembic.TemplateError, reason: reason
    end
  end

  @doc """
  Renders a pre-compiled AST against an assigns map.

  ## Examples

      iex> {:ok, ast} = Alembic.compile("Hello {{ name }}!")
      iex> Alembic.render(ast, %{"name" => "World"})
      {:ok, "Hello World!"}

      iex> {:ok, ast} = Alembic.compile("{{ missing }}")
      iex> Alembic.render(ast, %{}, strict: true)
      {:error, {:evaluator, {:undefined_variable, ["missing"]}}}
  """
  @spec render(AST.t(), map(), keyword()) :: {:ok, String.t()} | {:error, render_error()}
  def render(ast, assigns \\ %{}, opts \\ []) when is_list(ast) and is_map(assigns) do
    loader_fn = Loader.build_loader(opts)

    with {:ok, resolved_ast} <- inheritance_step(ast, loader_fn) do
      evaluator_step(resolved_ast, assigns, opts)
    end
  end

  @doc """
  Renders a pre-compiled AST against an assigns map, raising on error.
  """
  @spec render!(AST.t(), map(), keyword()) :: String.t()
  def render!(ast, assigns \\ %{}, opts \\ []) do
    case render(ast, assigns, opts) do
      {:ok, html} -> html
      {:error, reason} -> raise Alembic.TemplateError, reason: reason
    end
  end

  @doc """
  Compiles and renders a template string in one step.

  ## Examples

      iex> Alembic.render_string("Hi {{ user }}", %{"user" => "Alice"})
      {:ok, "Hi Alice"}
  """
  @spec render_string(String.t(), map(), keyword()) ::
          {:ok, String.t()} | {:error, compile_error() | render_error()}
  def render_string(source, assigns \\ %{}, opts \\ []) do
    with {:ok, ast} <- compile(source, opts) do
      render(ast, assigns, opts)
    end
  end

  @doc """
  Compiles and renders a template string in one step, raising on error.

  ## Examples

      iex> Alembic.render_string!("Hi {{ user }}", %{"user" => "Alice"})
      "Hi Alice"
  """
  @spec render_string!(String.t(), map(), keyword()) :: String.t()
  def render_string!(source, assigns \\ %{}, opts \\ []) do
    case render_string(source, assigns, opts) do
      {:ok, html} -> html
      {:error, reason} -> raise Alembic.TemplateError, reason: reason
    end
  end

  @doc """
  Loads, compiles (using the cache when enabled), and renders a template
  file resolved by name across the configured template roots.
  """
  @spec render_file(String.t(), map(), keyword()) ::
          {:ok, String.t()}
          | {:error, {:loader, Loader.reason()} | compile_error() | render_error()}
  def render_file(name, assigns \\ %{}, opts \\ []) do
    with {:ok, resolved_path} <- resolve_step(name, opts),
         {:ok, ast} <- compiled_ast_for(resolved_path, opts) do
      render(ast, assigns, opts)
    end
  end

  @doc """
  Loads, compiles, and renders a template file, raising on error.
  """
  @spec render_file!(String.t(), map(), keyword()) :: String.t()
  def render_file!(name, assigns \\ %{}, opts \\ []) do
    case render_file(name, assigns, opts) do
      {:ok, html} -> html
      {:error, reason} -> raise Alembic.TemplateError, reason: reason
    end
  end

  # ---- Pipeline steps ----

  defp lexer_step(source) do
    case Lexer.tokenize(source) do
      {:ok, tokens} -> {:ok, tokens}
      {:error, reason} -> {:error, {:lexer, reason}}
    end
  end

  defp parser_step(tokens) do
    case Parser.parse(tokens) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, {:parser, reason}}
    end
  end

  defp inheritance_step(ast, loader_fn) do
    case Inheritance.preprocess(ast, loader_fn) do
      {:ok, resolved} -> {:ok, resolved}
      {:error, reason} -> {:error, {:inheritance, reason}}
    end
  end

  defp evaluator_step(ast, assigns, opts) do
    strict? = Keyword.get(opts, :strict, false)

    ctx =
      assigns
      |> Context.new()
      |> Context.strict(strict?)
      |> Context.loader(Loader.build_loader(opts))

    case Evaluator.eval(ast, ctx) do
      {:ok, html} -> {:ok, html}
      {:error, reason} -> {:error, {:evaluator, reason}}
    end
  end

  defp resolve_step(name, opts) do
    case Loader.resolve_path(name, opts) do
      {:ok, path} -> {:ok, path}
      {:error, reason} -> {:error, {:loader, reason}}
    end
  end

  defp compiled_ast_for(resolved_path, opts) do
    if Keyword.get(opts, :cache, true) do
      cached_compile(resolved_path, opts)
    else
      read_and_compile(resolved_path, opts)
    end
  end

  defp cached_compile(resolved_path, opts) do
    case Cache.get(resolved_path) do
      {:hit, ast} ->
        {:ok, ast}

      :miss ->
        with {:ok, ast} <- read_and_compile(resolved_path, opts) do
          Cache.put(resolved_path, ast)
          {:ok, ast}
        end
    end
  end

  defp read_and_compile(resolved_path, opts) do
    with {:ok, source} <- read_step(resolved_path) do
      compile(source, opts)
    end
  end

  defp read_step(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, {:loader, reason}}
    end
  end
end

defmodule Alembic.TemplateError do
  @moduledoc """
  Raised by every bang (`!`) Alembic function (`compile!/2`, `render!/3`,
  `render_file!/3`) when the underlying non-bang call returns
  `{:error, reason}`.
  """

  defexception [:reason]

  @impl true
  def message(%__MODULE__{reason: reason}), do: "Alembic template error: #{inspect(reason)}"
end

defmodule Alembic.CompileError do
  @moduledoc """
  A more specific compile-time error than `Alembic.TemplateError` — carries
  the offending template source alongside the reason. Defined per issue
  1.5.3's task list for callers who want a narrower `rescue` clause; the
  bang functions themselves raise the general `Alembic.TemplateError`.
  """

  defexception [:reason, :template]

  @impl true
  def message(%__MODULE__{reason: reason, template: template}) do
    "Alembic compile error: #{inspect(reason)}" <> template_excerpt(template)
  end

  defp template_excerpt(nil), do: ""
  defp template_excerpt(template), do: " (template: #{inspect(String.slice(template, 0, 100))})"
end

defmodule Alembic.RenderError do
  @moduledoc """
  A more specific render-time error than `Alembic.TemplateError` — carries
  the template and a truncated view of the assigns alongside the reason.
  Defined per issue 1.5.3's task list for callers who want a narrower
  `rescue` clause; the bang functions themselves raise the general
  `Alembic.TemplateError`.
  """

  defexception [:reason, :template, :context]

  @impl true
  def message(%__MODULE__{reason: reason, context: context}) do
    "Alembic render error: #{inspect(reason)}" <> context_excerpt(context)
  end

  defp context_excerpt(nil), do: ""
  defp context_excerpt(context), do: " (context: #{inspect(context, limit: 5)})"
end
