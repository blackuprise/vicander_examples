defmodule WebShop.Domain.Product.Specs.StockNotNegative do
  @moduledoc "Stock is zero or more."
  use DDD.Specification, scope: :value

  @impl DDD.Specification
  def check(stock, _opts) when is_integer(stock) do
    if stock >= 0, do: :ok, else: {:error, :stock_negative, "can't be negative", %{}}
  end
end
