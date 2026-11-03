import Config

config :todo_app, TodoApp.Infrastructure.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "todo_app_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
