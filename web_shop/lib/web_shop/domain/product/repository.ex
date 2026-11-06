defmodule WebShop.Domain.Product.Repository do
  @moduledoc "Port: how the domain loads and saves products."
  use DDD.Repository

  repo WebShop.Domain.Product do
  end

  @doc "The adapter configured for this port."
  def impl, do: :web_shop |> Application.fetch_env!(:repositories) |> Keyword.fetch!(:product)
end
