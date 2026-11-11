defmodule TodoApp.Application.Commands.TodoList.CompleteItem do
  @moduledoc "Complete an item."
  use DDD.Command, retry_on_conflict: 3

  alias TodoApp.Domain.TodoList
  alias TodoApp.Domain.TodoList.Repository, as: TodoListRepository

  command do
    description "Mark an item of a todo list as done. An item that is already done is refused."

    field :list_id, :uuid,
      required: true,
      loads: TodoList,
      description: "The list the item belongs to"

    field :item_id, :uuid, required: true, description: "The item to complete"
  end

  @impl DDD.Command
  def execute(%__MODULE__{list_id: list_id, item_id: item_id}) do
    with {:ok, list} <- TodoListRepository.impl().find_by_id(list_id),
         {:ok, list} <- TodoList.complete_item(list, item_id) do
      TodoListRepository.impl().save(list)
    end
  end
end
