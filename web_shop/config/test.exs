import Config

config :web_shop, subscribe_handlers: false, start_outbox_poller: false

config :logger, :default_handler, level: if(System.get_env("LOG"), do: :all, else: :warning)

# Cheap hashing keeps the tests fast.
config :pbkdf2_elixir, rounds: 1

config :web_shop, WebShop.Infrastructure.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "web_shop_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  log: if(System.get_env("SQL"), do: :debug, else: false),
  pool_size: 10

config :web_shop, WebShop.Interface.Web.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base:
    "test-only-secret-key-base-test-only-secret-key-base-test-only-secret-key-base-0123"
