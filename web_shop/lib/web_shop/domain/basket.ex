defmodule WebShop.Domain.Basket do
  @moduledoc """
  Aggregate: a customer's basket (one per customer), holding what they intend to buy.

  Each line snapshots the product's name and price when it was added. Adding the same product
  again increases the quantity of its line. Checking out empties the basket (the order is a
  separate aggregate).
  """
  use DDD.Aggregate

  alias WebShop.Domain.Basket.{BasketItem, Events, Specs}

  aggregate do
    description "A customer's basket of products they may buy"

    identity :id, :uuid
    field :customer_id, {:ref, WebShop.Domain.User}, required: true, description: "The owner"
    field :items, {:list, BasketItem}, default: [], description: "The lines, oldest first"
  end

  @doc "Total price of the basket, in cents."
  @spec total_cents(struct()) :: non_neg_integer()
  def total_cents(%__MODULE__{items: items}),
    do: Enum.sum(Enum.map(items, &BasketItem.line_cents/1))

  @doc "Number of units in the basket."
  @spec quantity(struct()) :: non_neg_integer()
  def quantity(%__MODULE__{items: items}), do: Enum.sum(Enum.map(items, & &1.quantity))

  defop add_item(basket, %BasketItem{} = item) do
    with {:ok, items} <- merge(basket.items, item) do
      %{basket | items: items}
      |> emit_event(
        Events.ItemAdded.new(%{
          customer_id: basket.customer_id,
          quantity: item.quantity,
          amount_cents: BasketItem.line_cents(item)
        })
      )
    end
  end

  defop remove_item(basket, product_id), requires: Specs.ItemInBasket do
    {gone, kept} = Enum.split_with(basket.items, &(&1.product_id == product_id))
    [item] = gone

    %{basket | items: kept}
    |> emit_event(
      Events.ItemRemoved.new(%{
        customer_id: basket.customer_id,
        quantity: item.quantity,
        amount_cents: BasketItem.line_cents(item)
      })
    )
  end

  defop check_out(basket), requires: Specs.BasketNotEmpty do
    %{basket | items: []}
    |> emit_event(
      Events.CheckedOut.new(%{
        customer_id: basket.customer_id,
        quantity: quantity(basket),
        amount_cents: total_cents(basket)
      })
    )
  end

  defp merge(items, item) do
    case Enum.split_with(items, &(&1.product_id == item.product_id)) do
      {[], _} ->
        {:ok, items ++ [item]}

      {[existing], _} ->
        with {:ok, merged} <- BasketItem.add_quantity(existing, item.quantity) do
          {:ok, Enum.map(items, &if(&1.id == merged.id, do: merged, else: &1))}
        end
    end
  end
end
