defmodule WebShop.Domain.User.Specs.NameNotBlank do
  @moduledoc "A name has something in it besides spaces."
  use DDD.Specification, scope: :value

  @impl DDD.Specification
  def check(name, _opts) when is_binary(name) do
    if String.trim(name) == "", do: {:error, :name_blank, "can't be blank", %{}}, else: :ok
  end
end
