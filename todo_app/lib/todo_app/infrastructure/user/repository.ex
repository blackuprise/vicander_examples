defmodule TodoApp.Infrastructure.User.Repository do
  @moduledoc "Postgres adapter for `TodoApp.Domain.User.Repository`."
  use DDD.Repository.Ecto,
    port: TodoApp.Domain.User.Repository,
    repo: TodoApp.Infrastructure.Repo,
    table: "users"
end
