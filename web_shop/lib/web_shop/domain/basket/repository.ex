defmodule WebShop.Domain.Basket.Repository do
  @moduledoc "Port: how the domain loads and saves baskets."
  use DDD.Repository

  repo WebShop.Domain.Basket do
    find_by :customer_id
  end

  @doc "The adapter configured for this port."
  def impl, do: :web_shop |> Application.fetch_env!(:repositories) |> Keyword.fetch!(:basket)
end
