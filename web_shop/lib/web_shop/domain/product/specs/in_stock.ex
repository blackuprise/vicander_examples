defmodule WebShop.Domain.Product.Specs.InStock do
  @moduledoc "Precondition of `reserve`: enough is left. The quantity is the operation's argument."
  use DDD.Specification, field: :stock

  @impl DDD.Specification
  def check(%{stock: stock, name: name}, opts) do
    [quantity | _] = Keyword.fetch!(opts, :args)

    if stock >= quantity,
      do: :ok,
      else:
        {:error, :out_of_stock, "only #{stock} of #{name} left",
         %{stock: stock, wanted: quantity}}
  end
end
