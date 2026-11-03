defmodule TodoApp.Infrastructure.TodoList.Repository do
  @moduledoc "Postgres adapter for `TodoApp.Domain.TodoList.Repository` (one row per list)."
  use DDD.Repository.Ecto,
    port: TodoApp.Domain.TodoList.Repository,
    repo: TodoApp.Infrastructure.Repo,
    table: "todo_lists"
end
