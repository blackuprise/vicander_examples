defmodule WebShop.Domain.Order.Repository do
  @moduledoc "Port: how the domain loads and saves orders."
  use DDD.Repository

  repo WebShop.Domain.Order do
    find_by :customer_id
  end

  @doc "The adapter configured for this port."
  def impl, do: :web_shop |> Application.fetch_env!(:repositories) |> Keyword.fetch!(:order)
end
