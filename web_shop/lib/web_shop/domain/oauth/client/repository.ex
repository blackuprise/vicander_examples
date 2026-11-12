defmodule WebShop.Domain.OAuth.Client.Repository do
  @moduledoc "Port: how the domain loads and saves registered apps."
  use DDD.Repository

  repo WebShop.Domain.OAuth.Client do
  end

  @doc "The adapter configured for this port."
  def impl,
    do: :web_shop |> Application.fetch_env!(:repositories) |> Keyword.fetch!(:oauth_client)
end
