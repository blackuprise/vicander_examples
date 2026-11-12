defmodule WebShop.Boot do
  @moduledoc """
  The OTP application: the repo, PubSub, the framework's supervisor (event bus, projections,
  outbox poller) and the web endpoint.
  """
  use Application

  alias WebShop.Application.Projections.Basket.BasketOverview
  alias WebShop.Application.Projections.Order.DailySales
  alias WebShop.Infrastructure.Repo
  alias WebShop.Interface.Web.Endpoint

  @impl Application
  def start(_type, _args) do
    children =
      [
        Repo,
        {Phoenix.PubSub, name: WebShop.PubSub},
        {DDD.Supervisor, handlers: handlers(), poller: poller()}
      ] ++ web()

    Supervisor.start_link(children, strategy: :one_for_one, name: WebShop.Supervisor)
  end

  @impl Application
  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end

  # Tests turn this off (`subscribe_handlers: false`) and subscribe only what they need.
  defp handlers do
    if Application.get_env(:web_shop, :subscribe_handlers, true),
      do: [DailySales, BasketOverview],
      else: []
  end

  defp poller do
    if Application.get_env(:web_shop, :start_outbox_poller, true), do: [], else: false
  end

  # `mix shop.mcp` runs the application without the web server.
  defp web do
    if Application.get_env(:web_shop, :start_web, true), do: [Endpoint], else: []
  end
end
