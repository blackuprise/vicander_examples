defmodule TodoApp.Application.Commands.TodoList.RenameItem do
  @moduledoc "Rename an item."
  use DDD.Command, retry_on_conflict: 3

  alias TodoApp.Domain.TodoList
  alias TodoApp.Domain.TodoList.Repository, as: TodoListRepository
  alias TodoApp.Domain.TodoList.Title

  command do
    description "Change the title of an item. A completed item cannot be renamed."

    field :list_id, :uuid,
      required: true,
      loads: TodoList,
      description: "The list the item belongs to"

    field :item_id, :uuid, required: true, description: "The item to rename"
    field :title, :string, required: true, description: "The new title (at most 100 characters)"
  end

  @impl DDD.Command
  def execute(%__MODULE__{list_id: list_id, item_id: item_id, title: title}) do
    with {:ok, list} <- TodoListRepository.impl().find_by_id(list_id),
         {:ok, title} <- Title.new(value: title),
         {:ok, list} <- TodoList.rename_item(list, item_id, title) do
      TodoListRepository.impl().save(list)
    end
  end
end
