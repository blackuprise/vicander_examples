defmodule TodoApp.Infrastructure.Repo do
  @moduledoc """
  The application's Ecto repo (Postgres). The framework finds it through
  `config :vicander, repo: TodoApp.Infrastructure.Repo`.
  """
  use Ecto.Repo,
    otp_app: :todo_app,
    adapter: Ecto.Adapters.Postgres
end
