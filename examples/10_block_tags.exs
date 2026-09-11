# Run with: mix run examples/10_block_tags.exs
#
# Block-level tags: {% capture %}, {% unless %}, and {% case %}/{% when %}.

# {% capture %} renders its body into a variable, which behaves exactly like
# a variable set with {% assign %} — it's visible to every later node.
{:ok, output} =
  Alembic.render_string(
    "{% capture greeting %}Hello, {{ name }}!{% endcapture %}[{{ greeting }}]",
    %{"name" => "Alice"}
  )

IO.puts("capture:  #{output}")
# => capture:  [Hello, Alice!]

# The captured value is a plain string, so filters apply to it.
{:ok, output} =
  Alembic.render_string("{% capture x %}hi there{% endcapture %}{{ x | upcase }}", %{})

IO.puts("filtered: #{output}")
# => filtered: HI THERE

# {% unless %} is the negated form of {% if %}: the body renders when the
# condition is falsy. Remember Liquid truthiness — 0 is truthy.
{:ok, output} =
  Alembic.render_string(
    "{% unless logged_in %}Please sign in.{% else %}Welcome back.{% endunless %}",
    %{"logged_in" => false}
  )

IO.puts("unless:   #{output}")
# => unless:   Please sign in.

{:ok, output} =
  Alembic.render_string(
    "{% unless count %}no count{% else %}has count{% endunless %}",
    %{"count" => 0}
  )

IO.puts("truthy 0: #{output}")
# => truthy 0: has count

# {% case %}/{% when %} is multi-way branching on one subject. Each when may
# list several values, and an optional {% else %} covers no match.
case_template = """
{% case order.size %}\
{% when "small" %}Small order.\
{% when "medium", "large" %}Big order.\
{% else %}Unknown size.\
{% endcase %}\
"""

for size <- ["small", "large", "huge"] do
  {:ok, output} = Alembic.render_string(case_template, %{"order" => %{"size" => size}})
  IO.puts("case:     #{size} -> #{output}")
end

# => case:     small -> Small order.
# => case:     large -> Big order.
# => case:     huge -> Unknown size.
