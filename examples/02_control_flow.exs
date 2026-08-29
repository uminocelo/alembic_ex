
# Run with: mix run examples/02_control_flow.exs
#
# {% if %} / {% elsif %} / {% else %}, {% for %} with `forloop` metadata,
# and {% assign %}.

if_template = """
{% if user.role == "admin" %}
Welcome, administrator {{ user.name }}.
{% elsif user.role == "editor" %}
Welcome, editor {{ user.name }}.
{% else %}
Welcome, {{ user.name }}.
{% endif %}
"""

{:ok, admin_output} = Alembic.render_string(if_template, %{"user" => %{"role" => "admin", "name" => "Alice"}})
{:ok, guest_output} = Alembic.render_string(if_template, %{"user" => %{"role" => "guest", "name" => "Bob"}})
IO.puts(String.trim(admin_output))
IO.puts(String.trim(guest_output))
# => Welcome, administrator Alice.
# => Welcome, Bob.

# Liquid truthiness: only `nil` and `false` are falsy. `0` and `""` are
# truthy — this differs from many languages, including Elixir's own rules.
{:ok, output} = Alembic.render_string("{% if count %}has a count field{% else %}no count{% endif %}", %{"count" => 0})
IO.puts(output)
# => has a count field

# {% for %} with forloop metadata (index, index0, first, last, length).
for_template = """
{% for item in cart.items %}\
{{ forloop.index }}. {{ item.name }} (${{ item.price }})\
{% if forloop.last == false %}\n{% endif %}\
{% endfor %}
"""

cart = %{
  "items" => [
    %{"name" => "Coffee", "price" => 4},
    %{"name" => "Bagel", "price" => 3},
    %{"name" => "Juice", "price" => 5}
  ]
}

{:ok, output} = Alembic.render_string(for_template, %{"cart" => cart})
IO.puts(String.trim_trailing(output))
# => 1. Coffee ($4)
# => 2. Bagel ($3)
# => 3. Juice ($5)

# {% assign %} introduces a variable visible to every node rendered after
# it — including after the {% for %} loop it was set inside.
assign_template = """
{% for item in cart.items %}{% assign total = total | default: 0 | plus: item.price %}{% endfor %}\
Total: ${{ total }}\
"""

{:ok, output} = Alembic.render_string(assign_template, %{"cart" => cart})
IO.puts(output)
# => Total: $12
