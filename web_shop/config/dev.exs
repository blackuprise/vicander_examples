import Config

config :web_shop, WebShop.Infrastructure.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "web_shop_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :web_shop, WebShop.Interface.Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  server: true,
  debug_errors: true,
  # Development only: a fixed key. Production reads SECRET_KEY_BASE (config/runtime.exs).
  secret_key_base:
    "dev-only-secret-key-base-dev-only-secret-key-base-dev-only-secret-key-base-0123"

# `LOG=1 mix run --no-halt` logs every command, query, operation and event at debug level.
# Secrets are hidden by WebShop.Infrastructure.LogRedactor. `SQL=1` adds the SQL queries.
config :logger, :default_handler, level: if(System.get_env("LOG"), do: :debug, else: :info)

config :web_shop, WebShop.Infrastructure.Repo,
  log: if(System.get_env("SQL"), do: :debug, else: false)
