defmodule TodoApp.Infrastructure do
  @moduledoc """
  The infrastructure layer: adapters for the domain's ports (Postgres repositories) and
  technical event handlers. Depends on the domain, never the other way around.
  """
  use Boundary,
    top_level?: true,
    deps: [TodoApp.Domain],
    exports: [EventLogger, Repo, TodoList.Repository, User.Repository]
end
