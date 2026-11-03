defmodule TodoApp.Domain.TodoList.Repository do
  @moduledoc """
  Port: how the domain loads and saves todo lists.

  The domain declares the interface; an adapter in the infrastructure layer implements it.
  Which adapter is used is configuration (`config :todo_app, :repositories, todo_list: ...`),
  so callers never name one:

      TodoListRepository.impl().save(list)
  """
  use DDD.Repository

  repo TodoApp.Domain.TodoList do
    find_by :owner_id
  end

  @doc "The adapter configured for this port."
  def impl, do: :todo_app |> Application.fetch_env!(:repositories) |> Keyword.fetch!(:todo_list)
end
