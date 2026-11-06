defmodule WebShop.Application.Commands.Basket.RemoveFromBasket do
  @moduledoc "Remove a product's line from the customer's basket."
  use DDD.Command, retry_on_conflict: 3

  alias WebShop.Domain.Basket
  alias WebShop.Domain.Basket.Repository, as: BasketRepository
  alias WebShop.Domain.User

  command do
    description "Remove a product from a customer's basket"

    field :customer_id, {:ref, User}, required: true, loads: true, description: "The customer"
    field :product_id, :uuid, required: true, description: "The product to remove"
  end

  @impl DDD.Command
  def execute(%__MODULE__{customer_id: customer_id, product_id: product_id}) do
    case BasketRepository.impl().find_by_customer_id(customer_id) do
      [basket | _] ->
        with {:ok, basket} <- Basket.remove_item(basket, product_id) do
          BasketRepository.impl().save(basket)
        end

      [] ->
        {:error, {:item_not_in_basket, "that product is not in the basket"}}
    end
  end
end
