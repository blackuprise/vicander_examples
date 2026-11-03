defmodule TodoApp.Application.Commands.TodoList.Support do
  @moduledoc false

  alias TodoApp.Domain.TodoList.Repository, as: TodoListRepository

  def load_list(list_id) do
    case TodoListRepository.impl().find_by_id(list_id) do
      {:ok, list} -> {:ok, list}
      {:error, :not_found} -> {:error, {:list_not_found, "list #{list_id} does not exist"}}
    end
  end
end
