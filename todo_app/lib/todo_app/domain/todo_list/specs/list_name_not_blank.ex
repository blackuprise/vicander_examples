defmodule TodoApp.Domain.TodoList.Specs.ListNameNotBlank do
  @moduledoc "A name must contain something besides whitespace. A value spec (`on: :name`)."
  use DDD.Specification, scope: :value

  @impl DDD.Specification
  def check(name, _opts) when is_binary(name) do
    if String.trim(name) == "",
      do: {:error, :name_blank, "must not be blank"},
      else: :ok
  end

  def check(_name, _opts), do: :ok
end
