defmodule TodoApp.Domain.TodoList.Specs.TitleNotBlank do
  @moduledoc "A todo item's title must contain something besides whitespace."
  use DDD.Specification, field: :title

  @impl DDD.Specification
  def check(%{title: %{value: value}}, _opts) when is_binary(value) do
    if String.trim(value) == "",
      do: {:error, :title_blank, "title must not be blank"},
      else: :ok
  end

  def check(_entity, _opts), do: {:error, :title_blank, "title must not be blank"}
end
