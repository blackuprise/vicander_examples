defmodule WebShop.Application.Commands.Basket.AddToBasket do
  @moduledoc """
  Put a product in the customer's basket, creating the basket on first use.

  The basket is found by customer *before* anything is saved (a query after a save would raise
  `DDD.UnitOfWork.PendingChangesError`). Stock is not reserved here, only at checkout.
  """
  use DDD.Command, retry_on_conflict: 3

  alias WebShop.Domain.{Basket, Product, User}
  alias WebShop.Domain.Basket.BasketItem
  alias WebShop.Domain.Basket.Repository, as: BasketRepository
  alias WebShop.Domain.Product.Repository, as: ProductRepository

  command do
    description "Add a product to a customer's basket"

    field :customer_id, {:ref, User}, required: true, loads: true, description: "The customer"
    field :product_id, :uuid, required: true, loads: Product, description: "The product"
    field :quantity, :integer, default: 1, description: "How many (1 to 99 per product)"
  end

  @impl DDD.Command
  def execute(%__MODULE__{} = command) do
    with {:ok, basket} <- basket_of(command.customer_id),
         {:ok, product} <- ProductRepository.impl().find_by_id(command.product_id),
         {:ok, item} <-
           BasketItem.new(
             product_id: product.id,
             name: product.name,
             unit_price_cents: product.price_cents,
             quantity: command.quantity
           ),
         {:ok, basket} <- Basket.add_item(basket, item) do
      BasketRepository.impl().save(basket)
    end
  end

  defp basket_of(customer_id) do
    case BasketRepository.impl().find_by_customer_id(customer_id) do
      [basket | _] -> {:ok, basket}
      [] -> Basket.new(customer_id: customer_id)
    end
  end
end
