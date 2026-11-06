defmodule WebShop.Domain.Product.Specs.PricePositive do
  @moduledoc "A price is more than zero."
  use DDD.Specification, scope: :value

  @impl DDD.Specification
  def check(price, _opts) when is_integer(price) do
    if price > 0, do: :ok, else: {:error, :price_not_positive, "must be more than 0", %{}}
  end
end
