defmodule WebShop.Application.Commands.Product.AddProduct do
  @moduledoc "Add a product to the catalog. Admins only."
  use DDD.Command

  alias WebShop.Application.Authorize
  alias WebShop.Domain.Product
  alias WebShop.Domain.Product.Repository, as: ProductRepository
  alias WebShop.Domain.User

  command do
    description "Add a product to the catalog (admin only)"

    field :admin_id, {:ref, User}, required: true, loads: true, description: "The acting admin"
    field :name, :string, required: true, description: "The product name"
    field :description, :string, default: "", description: "A short description"
    field :price_cents, :integer, required: true, description: "The unit price in cents"
    field :stock, :integer, default: 0, description: "How many are in stock"
  end

  @impl DDD.Command
  def execute(%__MODULE__{} = command) do
    with :ok <- Authorize.admin(command.admin_id),
         {:ok, product} <-
           Product.new(
             name: command.name,
             description: command.description,
             price_cents: command.price_cents,
             stock: command.stock
           ) do
      ProductRepository.impl().save(product)
    end
  end
end
