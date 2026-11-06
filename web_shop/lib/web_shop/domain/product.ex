defmodule WebShop.Domain.Product do
  @moduledoc """
  Aggregate: an item for sale, with its price (in cents) and the stock left.

  Stock only changes through `reserve/2` (a purchase) and `restock/2` (an admin), and the stock
  can never go below zero.
  """
  use DDD.Aggregate

  alias WebShop.Domain.Product.Specs

  aggregate do
    description "An item for sale"

    identity :id, :uuid
    field :name, :string, required: true, description: "The product name"
    field :description, :string, default: "", description: "A short description"
    field :price_cents, :integer, required: true, description: "The unit price in cents"
    field :stock, :integer, default: 0, description: "How many are left"

    invariant Specs.NameNotBlank, on: :name
    invariant Specs.PricePositive, on: :price_cents
    invariant Specs.StockNotNegative, on: :stock
  end

  defop reserve(product, quantity) when is_integer(quantity) and quantity > 0,
    requires: Specs.InStock do
    %{product | stock: product.stock - quantity}
  end

  defop restock(product, quantity) when is_integer(quantity) and quantity > 0 do
    %{product | stock: product.stock + quantity}
  end
end
