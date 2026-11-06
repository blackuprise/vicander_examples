defmodule WebShop.Domain.Basket.Specs.QuantityInRange do
  @moduledoc "A line holds at least 1 and at most `:max` units."
  use DDD.Specification, scope: :value

  @impl DDD.Specification
  def check(quantity, opts) when is_integer(quantity) do
    max = Keyword.fetch!(opts, :max)

    if quantity in 1..max//1,
      do: :ok,
      else: {:error, :quantity_out_of_range, "must be between 1 and #{max}", %{max: max}}
  end
end
