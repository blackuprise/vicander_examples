defmodule WebShop.Application.Commands.Basket.CheckOut do
  @moduledoc """
  Turn the customer's basket into an order.

  One command, one transaction, one unit of work: it reads the basket and every product,
  reserves the stock (a product refuses more than it has), places the order and empties the
  basket. The products, the order, the basket and all their events are written together at the
  end, or nothing is. Two buyers racing for the last unit conflict on the product's version and
  the loser is re-run (`retry_on_conflict`), then told it is out of stock.
  """
  use DDD.Command, retry_on_conflict: 3

  alias WebShop.Domain.{Basket, Order, Product, User}
  alias WebShop.Domain.Basket.Repository, as: BasketRepository
  alias WebShop.Domain.Order.OrderLine
  alias WebShop.Domain.Order.Repository, as: OrderRepository
  alias WebShop.Domain.Product.Repository, as: ProductRepository

  command do
    description "Place an order for everything in the customer's basket"

    field :customer_id, {:ref, User}, required: true, loads: true, description: "The customer"
  end

  @impl DDD.Command
  def execute(%__MODULE__{customer_id: customer_id}) do
    with {:ok, basket} <- fetch_basket(customer_id),
         {:ok, emptied} <- Basket.check_out(basket),
         {:ok, products} <- reserve(basket.items),
         {:ok, lines} <- order_lines(basket.items),
         {:ok, order} <- Order.place(customer_id, lines),
         :ok <- save_all(products),
         {:ok, order} <- OrderRepository.impl().save(order),
         {:ok, _basket} <- BasketRepository.impl().save(emptied) do
      {:ok, order}
    end
  end

  defp fetch_basket(customer_id) do
    case BasketRepository.impl().find_by_customer_id(customer_id) do
      [basket | _] -> {:ok, basket}
      [] -> {:error, {:basket_empty, "the basket is empty"}}
    end
  end

  defp reserve(items) do
    items
    |> collect(fn item ->
      with {:ok, product} <- ProductRepository.impl().find_by_id(item.product_id) do
        Product.reserve(product, item.quantity)
      end
    end)
  end

  defp order_lines(items) do
    collect(items, fn item ->
      OrderLine.new(
        product_id: item.product_id,
        name: item.name,
        unit_price_cents: item.unit_price_cents,
        quantity: item.quantity
      )
    end)
  end

  defp save_all(products) do
    Enum.reduce_while(products, :ok, fn product, :ok ->
      case ProductRepository.impl().save(product) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp collect(items, fun) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end
end
