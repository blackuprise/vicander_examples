defmodule TodoApp.Domain.TodoList.Specs.MaxOpenItems do
  @moduledoc "A list holds at most `:max` (default 10) open items."
  use DDD.Specification, field: :items

  @default_max 10

  @impl DDD.Specification
  def check(%{items: items}, opts) do
    max = Keyword.get(opts, :max, @default_max)
    open = Enum.count(items, &(&1.status == :open))

    if open <= max,
      do: :ok,
      else:
        {:error, :too_many_open_items, "a list can have at most #{max} open items",
         %{max: max, open: open}}
  end
end
