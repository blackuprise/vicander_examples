defmodule TodoApp.Domain.TodoList.Specs.ItemExists do
  @moduledoc """
  Precondition of working on one item of a list: the list contains an item with that id.

  The id is the operation's first argument after the list (`opts[:args]`).
  """
  use DDD.Specification, field: :items

  @impl DDD.Specification
  def check(%{items: items}, opts) do
    [item_id | _] = Keyword.fetch!(opts, :args)

    if Enum.any?(items, &(&1.id == item_id)),
      do: :ok,
      else: {:error, :item_not_found, "no item #{item_id} in this list", %{item_id: item_id}}
  end
end
