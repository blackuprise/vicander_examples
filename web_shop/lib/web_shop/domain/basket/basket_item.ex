defmodule WebShop.Domain.Basket.BasketItem do
  @moduledoc "Entity inside a basket: one product line, with the name and price as they were added."
  use DDD.Entity

  entity do
    identity :id, :uuid
    field :product_id, :uuid, required: true
    field :name, :string, required: true
    field :unit_price_cents, :integer, required: true
    field :quantity, :integer, required: true

    invariant WebShop.Domain.Basket.Specs.QuantityInRange, on: :quantity, max: 99
  end

  @doc "The price of the line, in cents."
  @spec line_cents(struct()) :: non_neg_integer()
  def line_cents(%__MODULE__{unit_price_cents: price, quantity: quantity}), do: price * quantity

  defop add_quantity(item, extra) when is_integer(extra) do
    %{item | quantity: item.quantity + extra}
  end
end
