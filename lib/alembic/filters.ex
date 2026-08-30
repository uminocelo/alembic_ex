defmodule Alembic.Filters do
  @moduledoc """
  Built-in, Liquid-compatible filter library. Zero runtime dependencies —
  everything below uses only Elixir/OTP stdlib.

  Two intentional deviations from a literal reading of issue 1.4.3, both for
  correctness against real Liquid semantics:

  - `url_encode` / `url_decode` use `URI.encode_www_form/1` /
    `URI.decode_www_form/1` (space becomes `+`), not `URI.encode/1` /
    `URI.decode/1` — the latter percent-encodes spaces as `%20` and doesn't
    match Liquid's actual `url_encode` output.
  - `ceil` / `floor` return integers (`trunc(Float.ceil(x))`), matching
    Liquid, rather than `Float.ceil/1`'s own float return value.

  `join` with no argument defaults to `""` (empty separator) per issue
  1.4.3's explicit instruction, not Liquid's own default of `" "` — flagged
  here since it is a real behavioral divergence from upstream Liquid.

  ## Type coercion reference

  Every filter clause below is a private `apply_builtin/3` head, so none of
  them can carry their own `@doc` (the compiler warns — `@doc` has no effect
  on a private function). This table is the substitute: it's the single
  place documenting what each filter does when handed a value of the
  "wrong" type, instead of that behavior being scattered implicitly across
  56 private function clauses.

  ### Coerces to a string (`coerce_to_string/1`)

  `upcase`, `downcase`, `capitalize`, `strip`, `lstrip`, `rstrip`,
  `strip_newlines`, `prepend`, `append`, `replace`, `replace_first`,
  `remove`, `remove_first`, `split`, `truncate`, `truncatewords`,
  `newline_to_br`, `escape`, `escape_once`, `strip_html`, `url_encode`,
  `url_decode`, `base64_encode`, `base64_decode`, `sort_natural` (for
  comparison only — the original items are returned), `join`'s separator
  argument (not its items). `nil` coerces to `""`; numbers and booleans
  coerce via `Integer.to_string/1` / `Float.to_string/1` / `to_string/1`;
  anything else falls back to `inspect/1` rather than raising.

  `slice` also coerces its input via `coerce_to_string/1` — unlike upstream
  Liquid, it does not support slicing arrays, only strings (see
  `COMPATIBILITY.md`).

  ### Coerces to a number (`coerce_to_number/1`)

  `abs`, `ceil`, `floor`, `round`, `plus`, `minus`, `times`, `divided_by`,
  `modulo`, `at_least`, `at_most`. `nil` coerces to `0`, `true`/`false` to
  `1`/`0`, and a numeric string parses to an integer or float; a
  non-numeric string or any other type coerces to `0` rather than raising.

  ### No coercion — requires an exact type

  - `size` — matches only on `is_binary`/`is_list` guards; any other input
    falls through to the catch-all clause and returns
    `{:error, {:invalid_filter_args, "size", args}}`, not a crash.
  - `first`, `last`, `reverse`, `sort`, `uniq`, `compact`, `map`, `where`,
    `concat`, `push`, `pop`, `unshift`, `shift`, `flatten` — all expect a
    list; a non-list input raises (`FunctionClauseError` or
    `Protocol.UndefinedError`), the same as calling the underlying
    `List`/`Enum` function directly with that value.
  - `date` — accepts a `Date`/`DateTime`/`NaiveDateTime` struct or an ISO
    8601 string; anything else returns `{:error, {:invalid_date, value}}`,
    not a crash.
  - `default` — no coercion; blankness is an exact-value check against
    `nil`, `false`, `""`, and `[]` (see `blank?/1`), not a truthiness rule.
  - `inspect` — accepts any term as-is via `Kernel.inspect/1`; there is
    nothing to coerce.
  """

  @type reason ::
          {:unknown_filter, String.t()}
          | {:invalid_filter_args, String.t(), [any()]}
          | {:invalid_base64, String.t()}
          | {:invalid_date, any()}

  @doc """
  Applies a single named filter. Checks `custom_filters` first (matched by
  `c:Alembic.Filter.name/0`), then falls back to the built-in catalog.

  `custom_filters` defaults to `[]`; pass modules here for a per-call
  override (`Alembic.render/3`'s `:custom_filters` option) — they're tried
  before `config :alembic, :custom_filters` and take precedence on a name
  collision.

  ## Examples

      iex> Alembic.Filters.apply("upcase", "hello", [])
      {:ok, "HELLO"}

      iex> Alembic.Filters.apply("truncate", "hello world", [5])
      {:ok, "he..."}

      iex> Alembic.Filters.apply("nope", "x", [])
      {:error, {:unknown_filter, "nope"}}
  """
  @spec apply(String.t(), any(), [any()], [module()]) :: {:ok, any()} | {:error, reason()}
  def apply(name, value, args, custom_filters \\ []) do
    case custom_filter_module(name, custom_filters) do
      {:ok, module} -> module.apply(value, args)
      :not_found -> apply_builtin(name, value, args)
    end
  end

  @doc """
  Applies a full filter chain in order, the output of each filter feeding
  the next. Short-circuits on the first error. `ctx.custom_filters` (set
  via `Alembic.Context.custom_filters/2`) is consulted for every filter in
  the chain, ahead of the global `config :alembic, :custom_filters` list.

  ## Examples

      iex> Alembic.Filters.apply_chain("hello", [{"upcase", []}, {"truncate", [3, ""]}], nil)
      {:ok, "HEL"}

      iex> Alembic.Filters.apply_chain("hello", [], nil)
      {:ok, "hello"}
  """
  @spec apply_chain(any(), [{String.t(), [any()]}], Alembic.Context.t() | nil) ::
          {:ok, any()} | {:error, reason()}
  def apply_chain(value, filters, ctx) do
    custom_filters = context_custom_filters(ctx)

    Enum.reduce_while(filters, {:ok, value}, fn {name, args}, {:ok, acc} ->
      case __MODULE__.apply(name, acc, args, custom_filters) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp context_custom_filters(%Alembic.Context{custom_filters: modules}), do: modules
  defp context_custom_filters(_other), do: []

  defp custom_filter_module(name, custom_filters) do
    (custom_filters ++ Application.get_env(:alembic, :custom_filters, []))
    |> Enum.find(fn module -> module.name() == name end)
    |> case do
      nil -> :not_found
      module -> {:ok, module}
    end
  end

  # ---- String filters ----

  defp apply_builtin("upcase", value, []),
    do: {:ok, value |> coerce_to_string() |> String.upcase()}

  defp apply_builtin("downcase", value, []),
    do: {:ok, value |> coerce_to_string() |> String.downcase()}

  defp apply_builtin("capitalize", value, []),
    do: {:ok, value |> coerce_to_string() |> String.capitalize()}

  defp apply_builtin("strip", value, []), do: {:ok, value |> coerce_to_string() |> String.trim()}

  defp apply_builtin("lstrip", value, []),
    do: {:ok, value |> coerce_to_string() |> String.trim_leading()}

  defp apply_builtin("rstrip", value, []),
    do: {:ok, value |> coerce_to_string() |> String.trim_trailing()}

  defp apply_builtin("strip_newlines", value, []) do
    result =
      value
      |> coerce_to_string()
      |> String.replace("\r\n", "")
      |> String.replace("\n", "")
      |> String.replace("\r", "")

    {:ok, result}
  end

  defp apply_builtin("prepend", value, [prefix]),
    do: {:ok, coerce_to_string(prefix) <> coerce_to_string(value)}

  defp apply_builtin("append", value, [suffix]),
    do: {:ok, coerce_to_string(value) <> coerce_to_string(suffix)}

  defp apply_builtin("replace", value, [search, replacement]) do
    {:ok,
     String.replace(
       coerce_to_string(value),
       coerce_to_string(search),
       coerce_to_string(replacement)
     )}
  end

  defp apply_builtin("replace_first", value, [search, replacement]) do
    result =
      String.replace(
        coerce_to_string(value),
        coerce_to_string(search),
        coerce_to_string(replacement),
        global: false
      )

    {:ok, result}
  end

  defp apply_builtin("remove", value, [search]),
    do: {:ok, String.replace(coerce_to_string(value), coerce_to_string(search), "")}

  defp apply_builtin("remove_first", value, [search]) do
    {:ok, String.replace(coerce_to_string(value), coerce_to_string(search), "", global: false)}
  end

  defp apply_builtin("split", value, [delimiter]),
    do: {:ok, String.split(coerce_to_string(value), coerce_to_string(delimiter))}

  defp apply_builtin("truncate", value, [n]), do: {:ok, truncate(value, n, "...")}
  defp apply_builtin("truncate", value, [n, ellipsis]), do: {:ok, truncate(value, n, ellipsis)}
  defp apply_builtin("truncatewords", value, [n]), do: {:ok, truncatewords(value, n)}

  defp apply_builtin("newline_to_br", value, []),
    do: {:ok, String.replace(coerce_to_string(value), "\n", "<br />\n")}

  defp apply_builtin("escape", value, []), do: {:ok, escape(value)}
  defp apply_builtin("escape_once", value, []), do: {:ok, escape_once(value)}

  defp apply_builtin("strip_html", value, []),
    do: {:ok, Regex.replace(~r/<[^>]*>/, coerce_to_string(value), "")}

  defp apply_builtin("url_encode", value, []),
    do: {:ok, URI.encode_www_form(coerce_to_string(value))}

  defp apply_builtin("url_decode", value, []),
    do: {:ok, URI.decode_www_form(coerce_to_string(value))}

  defp apply_builtin("base64_encode", value, []),
    do: {:ok, Base.encode64(coerce_to_string(value))}

  defp apply_builtin("base64_decode", value, []) do
    case Base.decode64(coerce_to_string(value)) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, {:invalid_base64, value}}
    end
  end

  defp apply_builtin("size", value, []) when is_binary(value), do: {:ok, String.length(value)}
  defp apply_builtin("size", value, []) when is_list(value), do: {:ok, length(value)}

  defp apply_builtin("slice", value, [offset]),
    do: {:ok, String.slice(coerce_to_string(value), offset, 1)}

  defp apply_builtin("slice", value, [offset, length]),
    do: {:ok, String.slice(coerce_to_string(value), offset, length)}

  # ---- Array filters ----

  defp apply_builtin("join", value, []), do: {:ok, Enum.join(value, "")}

  defp apply_builtin("join", value, [separator]),
    do: {:ok, Enum.join(value, coerce_to_string(separator))}

  defp apply_builtin("first", value, []), do: {:ok, List.first(value)}
  defp apply_builtin("last", value, []), do: {:ok, List.last(value)}
  defp apply_builtin("reverse", value, []), do: {:ok, Enum.reverse(value)}
  defp apply_builtin("sort", value, []), do: {:ok, Enum.sort(value)}
  defp apply_builtin("sort", value, [key]), do: {:ok, Enum.sort_by(value, &item_key(&1, key))}

  defp apply_builtin("sort_natural", value, []) do
    {:ok, Enum.sort_by(value, &(&1 |> coerce_to_string() |> String.downcase()))}
  end

  defp apply_builtin("uniq", value, []), do: {:ok, Enum.uniq(value)}
  defp apply_builtin("compact", value, []), do: {:ok, Enum.reject(value, &is_nil/1)}
  defp apply_builtin("map", value, [key]), do: {:ok, Enum.map(value, &item_key(&1, key))}

  defp apply_builtin("where", value, [key]),
    do: {:ok, Enum.filter(value, &truthy?(item_key(&1, key)))}

  defp apply_builtin("where", value, [key, expected]),
    do: {:ok, Enum.filter(value, &(item_key(&1, key) == expected))}

  defp apply_builtin("concat", value, [other]), do: {:ok, value ++ other}
  defp apply_builtin("push", value, [item]), do: {:ok, value ++ [item]}
  defp apply_builtin("pop", value, []), do: {:ok, List.delete_at(value, -1)}
  defp apply_builtin("unshift", value, [item]), do: {:ok, [item | value]}
  defp apply_builtin("shift", [], []), do: {:ok, []}
  defp apply_builtin("shift", [_head | tail], []), do: {:ok, tail}
  defp apply_builtin("flatten", value, []), do: {:ok, List.flatten(value)}
  defp apply_builtin("flatten", value, [depth]), do: {:ok, flatten_to_depth(value, depth)}

  # ---- Number filters ----

  defp apply_builtin("abs", value, []), do: {:ok, abs(coerce_to_number(value))}
  defp apply_builtin("ceil", value, []), do: {:ok, value |> coerce_to_number() |> ceil_int()}
  defp apply_builtin("floor", value, []), do: {:ok, value |> coerce_to_number() |> floor_int()}
  defp apply_builtin("round", value, []), do: {:ok, value |> coerce_to_number() |> round_number()}

  defp apply_builtin("round", value, [precision]),
    do: {:ok, Float.round(coerce_to_number(value) * 1.0, precision)}

  defp apply_builtin("plus", value, [n]), do: {:ok, coerce_to_number(value) + coerce_to_number(n)}

  defp apply_builtin("minus", value, [n]),
    do: {:ok, coerce_to_number(value) - coerce_to_number(n)}

  defp apply_builtin("times", value, [n]),
    do: {:ok, coerce_to_number(value) * coerce_to_number(n)}

  defp apply_builtin("divided_by", value, [n]) do
    a = coerce_to_number(value)
    b = coerce_to_number(n)

    if is_integer(a) and is_integer(b) do
      {:ok, div(a, b)}
    else
      {:ok, a / b}
    end
  end

  defp apply_builtin("modulo", value, [n]),
    do: {:ok, rem(coerce_to_number(value), coerce_to_number(n))}

  defp apply_builtin("at_least", value, [n]),
    do: {:ok, max(coerce_to_number(value), coerce_to_number(n))}

  defp apply_builtin("at_most", value, [n]),
    do: {:ok, min(coerce_to_number(value), coerce_to_number(n))}

  # ---- Misc filters ----

  defp apply_builtin("default", value, [fallback]) do
    if blank?(value), do: {:ok, fallback}, else: {:ok, value}
  end

  defp apply_builtin("date", value, [format]), do: format_date(value, format)
  defp apply_builtin("inspect", value, []), do: {:ok, Kernel.inspect(value)}

  @known_filters ~w(
    upcase downcase capitalize strip lstrip rstrip strip_newlines prepend
    append replace replace_first remove remove_first split truncate
    truncatewords newline_to_br escape escape_once strip_html url_encode
    url_decode base64_encode base64_decode size slice join first last
    reverse sort sort_natural uniq compact map where concat push pop
    unshift shift flatten abs ceil floor round plus minus times divided_by
    modulo at_least at_most default date inspect
  )

  defp apply_builtin(name, _value, args) do
    if name in @known_filters do
      {:error, {:invalid_filter_args, name, args}}
    else
      {:error, {:unknown_filter, name}}
    end
  end

  # ---- Helpers ----

  defp item_key(item, key) when is_map(item),
    do: Map.get(item, key) || Map.get(item, safe_atom(key))

  defp item_key(item, key) when is_list(item), do: Keyword.get(item, safe_atom(key))
  defp item_key(_item, _key), do: nil

  defp safe_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(_other), do: true

  defp blank?(nil), do: true
  defp blank?(false), do: true
  defp blank?(""), do: true
  defp blank?([]), do: true
  defp blank?(_other), do: false

  defp truncate(value, n, ellipsis) do
    str = coerce_to_string(value)
    len = String.length(str)

    if len <= n do
      str
    else
      take = max(n - String.length(ellipsis), 0)
      String.slice(str, 0, take) <> ellipsis
    end
  end

  defp truncatewords(value, n) do
    words = value |> coerce_to_string() |> String.split(" ")

    if length(words) <= n do
      Enum.join(words, " ")
    else
      words |> Enum.take(n) |> Enum.join(" ") |> Kernel.<>("...")
    end
  end

  @escape_map %{"&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;", "'" => "&#39;"}

  defp escape(value) do
    value
    |> coerce_to_string()
    |> String.replace(["&", "<", ">", "\"", "'"], &Map.fetch!(@escape_map, &1))
  end

  @escape_once_pattern ~r/["><']|&(?!([a-zA-Z]+|#\d+);)/

  defp escape_once(value) do
    Regex.replace(@escape_once_pattern, coerce_to_string(value), &Map.fetch!(@escape_map, &1))
  end

  defp flatten_to_depth(list, 0), do: list

  defp flatten_to_depth(list, depth) do
    Enum.flat_map(list, fn
      item when is_list(item) -> flatten_to_depth(item, depth - 1)
      item -> [item]
    end)
  end

  defp ceil_int(n) when is_integer(n), do: n
  defp ceil_int(n) when is_float(n), do: n |> Float.ceil() |> trunc()

  defp floor_int(n) when is_integer(n), do: n
  defp floor_int(n) when is_float(n), do: n |> Float.floor() |> trunc()

  defp round_number(n) when is_integer(n), do: n
  defp round_number(n) when is_float(n), do: round(n)

  defp format_date(%DateTime{} = dt, format), do: {:ok, Calendar.strftime(dt, format)}
  defp format_date(%NaiveDateTime{} = dt, format), do: {:ok, Calendar.strftime(dt, format)}
  defp format_date(%Date{} = date, format), do: {:ok, Calendar.strftime(date, format)}

  defp format_date(value, format) when is_binary(value) do
    with {:error, _} <- DateTime.from_iso8601(value),
         {:error, _} <- parse_naive_date(value) do
      {:error, {:invalid_date, value}}
    else
      {:ok, dt} -> {:ok, Calendar.strftime(dt, format)}
      {:ok, dt, _offset} -> {:ok, Calendar.strftime(dt, format)}
    end
  end

  defp format_date(value, _format), do: {:error, {:invalid_date, value}}

  defp parse_naive_date(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> {:ok, naive}
      {:error, _} -> Date.from_iso8601(value)
    end
  end

  defp coerce_to_string(nil), do: ""
  defp coerce_to_string(value) when is_binary(value), do: value
  defp coerce_to_string(value) when is_integer(value), do: Integer.to_string(value)
  defp coerce_to_string(value) when is_float(value), do: Float.to_string(value)
  defp coerce_to_string(value) when is_boolean(value), do: to_string(value)

  defp coerce_to_string(value) do
    to_string(value)
  rescue
    Protocol.UndefinedError -> inspect(value)
  end

  defp coerce_to_number(value) when is_number(value), do: value
  defp coerce_to_number(nil), do: 0
  defp coerce_to_number(true), do: 1
  defp coerce_to_number(false), do: 0

  defp coerce_to_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} ->
        int

      _other ->
        case Float.parse(value) do
          {float, ""} -> float
          _other -> 0
        end
    end
  end

  defp coerce_to_number(_value), do: 0
end
