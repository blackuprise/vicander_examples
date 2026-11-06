defmodule WebShop.Application.Queries.Basket.ViewBasket do
  @moduledoc "What is in a customer's basket and what it costs (an empty basket if there is none)."
  use DDD.Query

  alias WebShop.Domain.Basket
  alias WebShop.Domain.Basket.BasketItem
  alias WebShop.Domain.Basket.Repository, as: BasketRepository

  query do
    description "The lines of a customer's basket, the number of units and the total in cents"

    field :customer_id, :uuid, required: true, description: "The customer"
  end

  @impl DDD.Query
  def execute(%__MODULE__{customer_id: customer_id}) do
    case BasketRepository.impl().find_by_customer_id(customer_id) do
      [basket | _] ->
        {:ok,
         %{
           items:
             for item <- basket.items do
               item
               |> Map.take([:product_id, :name, :unit_price_cents, :quantity])
               |> Map.put(:line_cents, BasketItem.line_cents(item))
             end,
           quantity: Basket.quantity(basket),
           total_cents: Basket.total_cents(basket)
         }}

      [] ->
        {:ok, %{items: [], quantity: 0, total_cents: 0}}
    end
  end
end
