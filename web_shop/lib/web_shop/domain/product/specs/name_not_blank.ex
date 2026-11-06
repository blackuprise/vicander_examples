defmodule WebShop.Domain.Product.Specs.NameNotBlank do
  @moduledoc "A product name has something in it besides spaces."
  use DDD.Specification, scope: :value

  @impl DDD.Specification
  def check(name, _opts) when is_binary(name) do
    if String.trim(name) == "", do: {:error, :name_blank, "can't be blank", %{}}, else: :ok
  end
end
