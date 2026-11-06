defmodule WebShop.Domain.Order.OrderLine do
  @moduledoc "Entity inside an order: a product, its price at checkout and the quantity."
  use DDD.Entity

  entity do
    identity :id, :uuid
    field :product_id, :uuid, required: true
    field :name, :string, required: true
    field :unit_price_cents, :integer, required: true
    field :quantity, :integer, required: true
  end

  @doc "The price of the line, in cents."
  @spec line_cents(struct()) :: non_neg_integer()
  def line_cents(%__MODULE__{unit_price_cents: price, quantity: quantity}), do: price * quantity
end
