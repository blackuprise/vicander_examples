defmodule WebShop.Application.Commands.Product.RestockProduct do
  @moduledoc "Add units to a product's stock. Admins only."
  use DDD.Command, retry_on_conflict: 3

  alias WebShop.Application.Authorize
  alias WebShop.Domain.Product
  alias WebShop.Domain.Product.Repository, as: ProductRepository
  alias WebShop.Domain.User

  command do
    description "Add units to a product's stock (admin only)"

    field :admin_id, {:ref, User}, required: true, loads: true, description: "The acting admin"
    field :product_id, :uuid, required: true, loads: Product, description: "The product"
    field :quantity, :integer, required: true, description: "How many units to add"
  end

  @impl DDD.Command
  def execute(%__MODULE__{} = command) do
    with :ok <- Authorize.admin(command.admin_id),
         {:ok, product} <- ProductRepository.impl().find_by_id(command.product_id),
         {:ok, product} <- Product.restock(product, command.quantity) do
      ProductRepository.impl().save(product)
    end
  end
end
