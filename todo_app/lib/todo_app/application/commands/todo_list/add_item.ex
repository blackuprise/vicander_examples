defmodule TodoApp.Application.Commands.TodoList.AddItem do
  @moduledoc "Add an item to a list."
  use DDD.Command

  alias TodoApp.Application.Commands.TodoList.Support
  alias TodoApp.Domain.TodoList
  alias TodoApp.Domain.TodoList.Repository, as: TodoListRepository
  alias TodoApp.Domain.TodoList.{Title, TodoItem}

  command do
    description "Add an item to a todo list. A list holds at most 10 open items."

    field :list_id, :uuid,
      required: true,
      description: "The list to add the item to"

    field :title, :string,
      required: true,
      description: "What needs doing (at most 100 characters)"

    field :due_date, :date,
      default: nil,
      description: "Optional due date, not in the past"

    field :priority, {:enum, [:low, :normal, :high]},
      default: :normal,
      description: "How important the item is"

    field :tags, {:array, :string},
      default: [],
      description: "Optional labels: at most 5, each at most 20 characters, none repeated"
  end

  @impl DDD.Command
  def execute(%__MODULE__{} = command) do
    with {:ok, list} <- Support.load_list(command.list_id),
         {:ok, title} <- Title.new(value: command.title),
         {:ok, item} <-
           TodoItem.new(
             title: title,
             due_date: command.due_date,
             priority: command.priority,
             tags: command.tags
           ),
         {:ok, list} <- TodoList.add_item(list, item) do
      TodoListRepository.impl().save(list)
    end
  end
end
