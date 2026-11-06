defmodule WebShop.CommandsTest do
  use WebShop.DataCase

  alias DDD.Error
  alias WebShop.Application.{Commands, Queries}
  alias WebShop.Domain.Product.Repository, as: Products

  describe "RegisterUser" do
    test "stores a hash, never the password, and lowercases the email" do
      user =
        Commands.User.RegisterUser.call!(%{
          name: "Ann",
          email: " Ann@Example.com ",
          password: "long-enough-password"
        })

      assert user.email == "ann@example.com"
      assert user.role == :customer
      refute user.password_hash =~ "long-enough-password"
    end

    test "refuses a taken email and a short password, naming the fields" do
      register!()

      assert {:error, error} =
               Commands.User.RegisterUser.call(%{
                 name: "Bob",
                 email: "ann@example.com",
                 password: "long-enough-password"
               })

      assert Error.to_map(error) == %{email: ["is already registered"]}

      assert {:error, error} =
               Commands.User.RegisterUser.call(%{
                 name: "Bob",
                 email: "bob@example.com",
                 password: "short"
               })

      assert %{password: [_]} = Error.to_map(error)
    end
  end

  describe "Authenticate" do
    test "accepts the right password and gives the same answer for a wrong one and an unknown email" do
      user = register!()

      assert {:ok, %{id: id, role: :customer} = found} =
               Queries.User.Authenticate.call(%{
                 email: "ANN@example.com",
                 password: "long-enough-password"
               })

      assert id == user.id
      refute Map.has_key?(found, :password_hash)

      assert {:error, wrong} =
               Queries.User.Authenticate.call(%{
                 email: "ann@example.com",
                 password: "nope-nope-nope"
               })

      assert {:error, unknown} =
               Queries.User.Authenticate.call(%{
                 email: "who@example.com",
                 password: "nope-nope-nope"
               })

      assert wrong.code == :invalid_credentials
      assert wrong.message == unknown.message
    end
  end

  describe "admin only commands" do
    test "a customer cannot add or restock products" do
      customer = register!()

      assert {:error, %Error{code: :forbidden}} =
               Commands.Product.AddProduct.call(%{
                 admin_id: customer.id,
                 name: "Mug",
                 price_cents: 100
               })

      product = product!(admin!())

      assert {:error, %Error{code: :forbidden}} =
               Commands.Product.RestockProduct.call(%{
                 admin_id: customer.id,
                 product_id: product.id,
                 quantity: 5
               })

      assert {:error, %Error{code: :forbidden}} =
               Queries.Report.ShopReport.call(%{admin_id: customer.id})

      assert {:error, %Error{code: :forbidden}} =
               Queries.Basket.PendingBaskets.call(%{admin_id: customer.id})
    end

    test "an admin adds and restocks, and invalid products are refused" do
      admin = admin!()
      product = product!(admin, %{stock: 3})

      assert {:ok, restocked} =
               Commands.Product.RestockProduct.call(%{
                 admin_id: admin.id,
                 product_id: product.id,
                 quantity: 10
               })

      assert restocked.stock == 13

      assert {:error, error} =
               Commands.Product.AddProduct.call(%{
                 admin_id: admin.id,
                 name: " ",
                 price_cents: 0,
                 stock: 1
               })

      assert %{name: _, price_cents: _} = Error.to_map(error)
    end
  end

  describe "catalog" do
    test "lists products by name and searches part of a name, treating % literally" do
      admin = admin!()
      product!(admin, %{name: "Blue mug"})
      product!(admin, %{name: "Red mug"})
      product!(admin, %{name: "Kettle"})

      assert {:ok, %{products: all, total_products: 3}} = Queries.Product.ListProducts.call(%{})
      assert Enum.map(all, & &1.name) == ["Blue mug", "Kettle", "Red mug"]

      assert {:ok, %{products: [%{name: "Red mug"}]}} =
               Queries.Product.ListProducts.call(%{search: "red"})

      assert {:ok, %{products: []}} = Queries.Product.ListProducts.call(%{search: "%"})
    end
  end

  describe "basket" do
    setup do
      customer = register!()
      %{customer: customer, product: product!(admin!())}
    end

    test "adding the same product twice makes one line", %{customer: customer, product: product} do
      add_to_basket!(customer, product, 2)
      add_to_basket!(customer, product, 3)

      assert {:ok, %{items: [line], quantity: 5, total_cents: 6250}} =
               Queries.Basket.ViewBasket.call(%{customer_id: customer.id})

      assert line.quantity == 5
    end

    test "a line is limited to 99 units", %{customer: customer, product: product} do
      add_to_basket!(customer, product, 99)

      assert {:error, error} =
               Commands.Basket.AddToBasket.call(%{
                 customer_id: customer.id,
                 product_id: product.id,
                 quantity: 1
               })

      assert Error.has_code?(error, :quantity_out_of_range)
    end

    test "removing a line, and removing one that is not there", %{
      customer: customer,
      product: product
    } do
      add_to_basket!(customer, product)

      assert {:ok, _} =
               Commands.Basket.RemoveFromBasket.call(%{
                 customer_id: customer.id,
                 product_id: product.id
               })

      assert {:ok, %{items: []}} = Queries.Basket.ViewBasket.call(%{customer_id: customer.id})

      assert {:error, error} =
               Commands.Basket.RemoveFromBasket.call(%{
                 customer_id: customer.id,
                 product_id: product.id
               })

      assert Error.has_code?(error, :item_not_in_basket)
    end
  end

  describe "CheckOut" do
    setup do
      admin = admin!()

      %{
        customer: register!(),
        mug: product!(admin, %{stock: 5}),
        pot: product!(admin, %{name: "Pot", price_cents: 4000, stock: 1})
      }
    end

    test "places the order, takes the stock and empties the basket", %{
      customer: customer,
      mug: mug,
      pot: pot
    } do
      add_to_basket!(customer, mug, 2)
      add_to_basket!(customer, pot, 1)

      assert {:ok, order} = Commands.Basket.CheckOut.call(%{customer_id: customer.id})
      assert order.total_cents == 2 * 1250 + 4000
      assert length(order.lines) == 2

      assert {:ok, %{stock: 3}} = Products.impl().find_by_id(mug.id)
      assert {:ok, %{stock: 0}} = Products.impl().find_by_id(pot.id)

      assert {:ok, %{items: [], quantity: 0}} =
               Queries.Basket.ViewBasket.call(%{customer_id: customer.id})

      assert {:ok, %{orders: [%{total_cents: 6500}]}} =
               Queries.Order.OrdersOfCustomer.call(%{customer_id: customer.id})
    end

    test "is all or nothing when one product is out of stock", %{
      customer: customer,
      mug: mug,
      pot: pot
    } do
      add_to_basket!(customer, mug, 2)
      add_to_basket!(customer, pot, 1)

      # someone else buys the last pot first
      other = register!("other@example.com")
      add_to_basket!(other, pot, 1)
      assert {:ok, _} = Commands.Basket.CheckOut.call(%{customer_id: other.id})

      assert {:error, error} = Commands.Basket.CheckOut.call(%{customer_id: customer.id})
      assert Error.has_code?(error, :out_of_stock)
      assert {:ok, %{stock: 5}} = Products.impl().find_by_id(mug.id)
      assert {:ok, %{quantity: 3}} = Queries.Basket.ViewBasket.call(%{customer_id: customer.id})

      assert {:ok, %{orders: []}} =
               Queries.Order.OrdersOfCustomer.call(%{customer_id: customer.id})
    end

    test "refuses an empty basket, and a customer with no basket at all", %{
      customer: customer,
      mug: mug
    } do
      assert {:error, %Error{code: :basket_empty}} =
               Commands.Basket.CheckOut.call(%{customer_id: customer.id})

      add_to_basket!(customer, mug)

      {:ok, _} =
        Commands.Basket.RemoveFromBasket.call(%{customer_id: customer.id, product_id: mug.id})

      assert {:error, error} = Commands.Basket.CheckOut.call(%{customer_id: customer.id})
      assert Error.has_code?(error, :basket_empty)
    end
  end
end
