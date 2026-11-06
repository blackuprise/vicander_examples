defmodule WebShop.Domain.Basket.Specs.ItemInBasket do
  @moduledoc "Precondition of `remove_item`: the basket has a line for that product."
  use DDD.Specification, field: :items

  @impl DDD.Specification
  def check(%{items: items}, opts) do
    [product_id | _] = Keyword.fetch!(opts, :args)

    if Enum.any?(items, &(&1.product_id == product_id)),
      do: :ok,
      else: {:error, :item_not_in_basket, "that product is not in the basket", %{}}
  end
end
