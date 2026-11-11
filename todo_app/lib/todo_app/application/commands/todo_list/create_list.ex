defmodule TodoApp.Application.Commands.TodoList.CreateList do
  @moduledoc """
  Create a todo list for an existing user.

  "The owner exists" needs the database, so it is not a spec: `loads:` reads the owner before
  the command runs, and fails it with `:not_found` if there is none.
  """
  use DDD.Command

  alias TodoApp.Domain.TodoList
  alias TodoApp.Domain.TodoList.Repository, as: TodoListRepository

  command do
    description "Create an empty todo list for an existing user"

    field :owner_id, {:ref, TodoApp.Domain.User},
      required: true,
      loads: true,
      description: "The id of the user who owns the list"

    field :name, :string, required: true, description: "The name of the list; not blank"
  end

  @impl DDD.Command
  def execute(%__MODULE__{owner_id: owner_id, name: name}) do
    with {:ok, list} <- TodoList.new(owner_id: owner_id, name: name) do
      TodoListRepository.impl().save(list)
    end
  end
end
