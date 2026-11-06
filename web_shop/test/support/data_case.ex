defmodule WebShop.DataCase do
  @moduledoc """
  Test case for tests that hit Postgres. Each test runs in a sandbox transaction shared with
  other processes (the outbox poller), so these tests are not async. It also has the helpers
  every test needs to set up users, products and baskets through the real commands.
  """
  use ExUnit.CaseTemplate

  alias WebShop.Application.Commands

  using do
    quote do
      import WebShop.DataCase
      alias WebShop.Infrastructure.Repo
    end
  end

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(WebShop.Infrastructure.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  def register!(email \\ "ann@example.com", role \\ :customer) do
    Commands.User.RegisterUser.call!(%{
      name: "Ann",
      email: email,
      password: "long-enough-password",
      role: role
    })
  end

  def admin!, do: register!("admin@example.com", :admin)

  def product!(admin, attrs \\ %{}) do
    Commands.Product.AddProduct.call!(
      Map.merge(
        %{admin_id: admin.id, name: "Mug", description: "A mug", price_cents: 1250, stock: 10},
        attrs
      )
    )
  end

  def add_to_basket!(customer, product, quantity \\ 1) do
    Commands.Basket.AddToBasket.call!(%{
      customer_id: customer.id,
      product_id: product.id,
      quantity: quantity
    })
  end
end
