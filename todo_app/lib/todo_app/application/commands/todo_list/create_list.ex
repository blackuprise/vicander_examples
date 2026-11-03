defmodule TodoApp.Application.Commands.TodoList.CreateList do
  @moduledoc """
  Create a todo list for an existing user.

  "The owner exists" needs the database, so it is checked here and not in a spec.
  """
  use DDD.Command

  alias TodoApp.Domain.TodoList
  alias TodoApp.Domain.TodoList.Repository, as: TodoListRepository
  alias TodoApp.Domain.User.Repository, as: UserRepository

  command do
    description "Create an empty todo list for an existing user"

    field :owner_id, {:ref, TodoApp.Domain.User},
      required: true,
      description: "The id of the user who owns the list"

    field :name, :string, required: true, description: "The name of the list; not blank"
  end

  @impl DDD.Command
  def execute(%__MODULE__{owner_id: owner_id, name: name}) do
    with {:ok, _owner} <- find_owner(owner_id),
         {:ok, list} <- TodoList.new(owner_id: owner_id, name: name) do
      TodoListRepository.impl().save(list)
    end
  end

  defp find_owner(owner_id) do
    case UserRepository.impl().find_by_id(owner_id) do
      {:ok, owner} -> {:ok, owner}
      {:error, :not_found} -> {:error, {:owner_not_found, "owner #{owner_id} does not exist"}}
    end
  end
end
