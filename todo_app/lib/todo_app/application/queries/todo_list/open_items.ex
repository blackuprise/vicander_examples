defmodule TodoApp.Application.Queries.TodoList.OpenItems do
  @moduledoc "The items of a list that are not done yet, optionally of one priority."
  use DDD.Query

  alias TodoApp.Domain.TodoList.Repository, as: TodoListRepository

  query do
    description "The items of a todo list that are not done yet, with their priority, tags and due dates"

    field :list_id, :uuid, required: true, description: "The list to read"

    field :priority, {:enum, [:low, :normal, :high]},
      description: "Only the items of this priority (default: all of them)"
  end

  @impl DDD.Query
  def execute(%__MODULE__{list_id: list_id, priority: priority}) do
    case TodoListRepository.impl().find_by_id(list_id) do
      {:ok, list} ->
        {:ok,
         for item <- list.items, item.status == :open, priority in [nil, item.priority] do
           %{
             id: item.id,
             title: item.title.value,
             priority: item.priority,
             tags: item.tags,
             due_date: item.due_date
           }
         end}

      {:error, :not_found} ->
        {:error, {:list_not_found, "list #{list_id} does not exist"}}
    end
  end
end
