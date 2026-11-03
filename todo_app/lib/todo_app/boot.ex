defmodule TodoApp.Boot do
  @moduledoc """
  The OTP application: starts the repo and the framework's supervisor (event bus, handler
  subscriptions, outbox poller, dead-letter handler).
  """
  use Application

  alias TodoApp.Application.Handlers.User.AchievementTracker
  alias TodoApp.Application.Projections.TodoList.ListStats
  alias TodoApp.Infrastructure.{EventLogger, Repo}

  @impl Application
  def start(_type, _args) do
    children = [
      Repo,
      {DDD.Supervisor, handlers: handlers(), poller: poller()}
    ]

    children = children ++ http()

    Supervisor.start_link(children, strategy: :one_for_one, name: TodoApp.Supervisor)
  end

  # Tests turn this off (`subscribe_handlers: false`) and subscribe only what they need, so
  # handlers never run against a finished test.
  defp handlers do
    if Application.get_env(:todo_app, :subscribe_handlers, true),
      do: [EventLogger, AchievementTracker, ListStats],
      else: []
  end

  # The demo HTTP API (`TodoApp.Interface.HTTP`) listens on `config :todo_app, http_port: 4000`,
  # unless `config :todo_app, start_http: false` (tests).
  defp http do
    if Application.get_env(:todo_app, :start_http, true) do
      port = Application.get_env(:todo_app, :http_port, 4000)
      [{Bandit, plug: TodoApp.Interface.HTTP, port: port}]
    else
      []
    end
  end

  # The outbox is polled unless `config :todo_app, start_outbox_poller: false`.
  defp poller do
    if Application.get_env(:todo_app, :start_outbox_poller, true), do: [], else: false
  end
end
