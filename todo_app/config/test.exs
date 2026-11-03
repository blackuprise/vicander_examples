import Config

# Tests subscribe the handlers they need, and no outbox poller runs unless a test starts one.
config :todo_app, subscribe_handlers: false, start_outbox_poller: false, start_http: false

# Test output is quiet by default (warnings and errors only).
# `LOG=1 mix test` shows the app flow: commands, operations, repositories, outbox, events.
# Add `SQL=1` to also see the SQL queries.
config :logger, :default_handler, level: if(System.get_env("LOG"), do: :all, else: :warning)

config :todo_app, TodoApp.Infrastructure.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "todo_app_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  # SQL queries are logged only with `SQL=1` (together with `LOG=1`).
  log: if(System.get_env("SQL"), do: :debug, else: false),
  pool_size: 10
