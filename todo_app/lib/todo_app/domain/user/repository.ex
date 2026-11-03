defmodule TodoApp.Domain.User.Repository do
  @moduledoc """
  Port: how the domain loads and saves users. The adapter is chosen by configuration
  (`config :todo_app, :repositories, user: ...`); callers use `impl/0` and never name one.
  """
  use DDD.Repository

  repo TodoApp.Domain.User do
    find_by :email
  end

  @doc "The adapter configured for this port."
  def impl, do: :todo_app |> Application.fetch_env!(:repositories) |> Keyword.fetch!(:user)
end
