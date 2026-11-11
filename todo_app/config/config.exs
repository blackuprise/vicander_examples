import Config

config :todo_app, ecto_repos: [TodoApp.Infrastructure.Repo]

# The framework (the `vicander` library) needs to know the application's repo.
config :vicander, repo: TodoApp.Infrastructure.Repo

# Which adapter implements each of the domain's repository ports. The application layer only
# ever names the port (`TodoListRepository.impl()`), so swapping an adapter is a config change.
config :todo_app, :repositories,
  todo_list: TodoApp.Infrastructure.TodoList.Repository,
  user: TodoApp.Infrastructure.User.Repository

# Where each aggregate is stored, for `loads:` on a command field. The application layer names the
# aggregate; the port gives the adapter configured above.
config :vicander, :repositories, [
  {TodoApp.Domain.TodoList, TodoApp.Domain.TodoList.Repository},
  {TodoApp.Domain.User, TodoApp.Domain.User.Repository}
]

# What `DDD.Health` (and `mix vic.health`) checks besides the database and the outbox: the
# projections that must not fall behind.
config :vicander, :health, projections: [TodoApp.Application.Projections.TodoList.ListStats]

import_config "#{config_env()}.exs"
