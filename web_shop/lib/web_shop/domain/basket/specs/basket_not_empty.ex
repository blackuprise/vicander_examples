defmodule WebShop.Domain.Basket.Specs.BasketNotEmpty do
  @moduledoc "Precondition of `check_out`: there is something to buy."
  use DDD.Specification, field: :items

  @impl DDD.Specification
  def check(%{items: []}, _opts), do: {:error, :basket_empty, "the basket is empty", %{}}
  def check(%{items: _}, _opts), do: :ok
end
