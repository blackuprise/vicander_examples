defmodule WebShop.MCPTest do
  # The shop through its MCP server, as a customer and as an admin, against the real database.
  use WebShop.DataCase

  alias WebShop.Interface.MCP, as: Server
  alias WebShop.Interface.MCP.Policy

  @password "long-enough-password"

  setup do
    Policy.sign_out()
    for var <- ~w(SHOP_MCP_EMAIL SHOP_MCP_PASSWORD), do: System.delete_env(var)

    on_exit(fn ->
      Policy.sign_out()
      for var <- ~w(SHOP_MCP_EMAIL SHOP_MCP_PASSWORD), do: System.delete_env(var)
      Application.delete_env(:web_shop, :mcp_email)
    end)
  end

  defp rpc(method, params \\ nil) do
    message = %{"jsonrpc" => "2.0", "id" => 1, "method" => method}
    message = if params, do: Map.put(message, "params", params), else: message
    {:reply, response} = Server.handle(message)
    response
  end

  defp call(name, arguments \\ %{}) do
    %{"result" => result} = rpc("tools/call", %{"name" => name, "arguments" => arguments})
    result
  end

  defp text(result), do: get_in(result, ["content", Access.at(0), "text"])

  defp data(result) do
    assert result["isError"] == false, inspect(result)
    result |> text() |> Jason.decode!()
  end

  defp refused(result) do
    assert result["isError"] == true, inspect(result)
    text(result)
  end

  defp sign_in!(user) do
    assert {:ok, _} = Policy.sign_in(user.email, @password)
    user
  end

  # A shop with an admin, a product, and two customers who each have something in a basket.
  defp shop! do
    admin = admin!()
    mug = product!(admin, %{name: "Blue mug", stock: 6})
    ann = register!("ann@example.com")
    bob = register!("bob@example.com")
    add_to_basket!(ann, mug, 2)
    add_to_basket!(bob, mug, 1)
    %{admin: admin, mug: mug, ann: ann, bob: bob}
  end

  test "what the server offers: the queries and one command, each described" do
    tools = rpc("tools/list")["result"]["tools"]

    assert tools |> Enum.map(& &1["name"]) |> Enum.sort() ==
             ~w(list_products me orders_of_customer pending_baskets restock_product shop_report
                view_basket)

    assert Enum.all?(tools, &(String.length(&1["description"]) > 10))

    for tool <- tools, {name, schema} <- tool["inputSchema"]["properties"] do
      assert schema["description"], "#{tool["name"]}.#{name} has no description"
    end

    # Of everything that changes data, only the admin's restock is offered, and nothing that
    # takes or returns a password.
    names = Enum.map(tools, & &1["name"])

    for hidden <- ~w(register_user authenticate get_user check_out add_to_basket
                     remove_from_basket add_product) do
      refute hidden in names
    end
  end

  describe "without a login" do
    test "every call is refused and says how to sign in" do
      for name <- ~w(me list_products), do: assert(refused(call(name)) =~ "Not signed in")
    end

    test "a wrong password is refused, not guessed again as another user" do
      register!("ann@example.com")
      System.put_env("SHOP_MCP_EMAIL", "ann@example.com")
      System.put_env("SHOP_MCP_PASSWORD", "not-the-password")

      assert refused(call("me")) =~ "Sign-in failed"
    end

    test "the first call signs in with the environment, and the session is kept" do
      ann = register!("ann@example.com")
      System.put_env("SHOP_MCP_EMAIL", "ann@example.com")
      System.put_env("SHOP_MCP_PASSWORD", @password)

      assert %{"id" => id, "email" => "ann@example.com", "role" => "customer"} = data(call("me"))
      assert id == ann.id

      # Signed in once: the environment is not read again.
      System.delete_env("SHOP_MCP_PASSWORD")
      assert data(call("me"))["id"] == ann.id
    end

    test "the email can come from the --email option of the task" do
      ann = register!("ann@example.com")
      Mix.Tasks.Shop.Mcp.prepare(email: "ann@example.com")
      System.put_env("SHOP_MCP_PASSWORD", @password)

      assert data(call("me"))["id"] == ann.id
    end

    test "an empty email or password is 'not signed in', not a wrong password" do
      register!("ann@example.com")

      for {email, password} <- [{"ann@example.com", ""}, {"", @password}, {" ", " "}] do
        System.put_env("SHOP_MCP_EMAIL", email)
        System.put_env("SHOP_MCP_PASSWORD", password)

        assert refused(call("me")) =~ "Not signed in"
      end
    end
  end

  describe "as a customer" do
    setup do
      shop = shop!()
      sign_in!(shop.ann)
      shop
    end

    test "knows who they are and can browse the products", %{ann: ann} do
      assert %{"id" => id, "role" => "customer"} = data(call("me"))
      assert id == ann.id

      assert %{"products" => [%{"name" => "Blue mug"}]} =
               data(call("list_products", %{"search" => "mug"}))
    end

    test "reads their own basket and orders", %{ann: ann} do
      assert %{"quantity" => 2} = data(call("view_basket", %{"customer_id" => ann.id}))
      assert %{"orders" => []} = data(call("orders_of_customer", %{"customer_id" => ann.id}))
    end

    test "can not read another customer's basket or orders", %{bob: bob, ann: ann} do
      for tool <- ~w(view_basket orders_of_customer) do
        message = refused(call(tool, %{"customer_id" => bob.id}))
        assert message =~ "only read your own"
        assert message =~ ann.id
      end
    end

    test "can not read the admin reports, whoever they say they are", %{ann: ann, admin: admin} do
      for tool <- ~w(shop_report pending_baskets), id <- [ann.id, admin.id] do
        assert refused(call(tool, %{"admin_id" => id})) =~ "Admins only"
      end
    end

    test "can not restock, whoever they say they are", %{ann: ann, admin: admin, mug: mug} do
      for id <- [ann.id, admin.id] do
        arguments = %{"admin_id" => id, "product_id" => mug.id, "quantity" => 5}
        assert refused(call("restock_product", arguments)) =~ "Admins only"
      end

      assert stock_of("mug") == 6
    end
  end

  describe "as an admin" do
    setup do
      shop = shop!()
      sign_in!(shop.admin)
      shop
    end

    test "is told so", %{admin: admin} do
      assert %{"id" => id, "role" => "admin"} = data(call("me"))
      assert id == admin.id
    end

    test "reads any customer's basket and orders", %{ann: ann, bob: bob} do
      assert %{"quantity" => 2} = data(call("view_basket", %{"customer_id" => ann.id}))
      assert %{"quantity" => 1} = data(call("view_basket", %{"customer_id" => bob.id}))
      assert %{"orders" => []} = data(call("orders_of_customer", %{"customer_id" => bob.id}))
    end

    test "reads the shop report and the pending baskets, as themselves", %{admin: admin} do
      assert %{"week" => [_ | _]} = data(call("shop_report", %{"admin_id" => admin.id}))

      # A list of baskets. The tests run without the read-model handlers, so it is empty here.
      assert [] = data(call("pending_baskets", %{"admin_id" => admin.id}))
    end

    test "can not borrow another admin's id", %{ann: ann} do
      assert refused(call("shop_report", %{"admin_id" => ann.id})) =~ "Pass your own id"
    end

    test "restocks a product, and the shop sees the new stock", %{admin: admin, mug: mug} do
      assert stock_of("mug") == 6

      arguments = %{"admin_id" => admin.id, "product_id" => mug.id, "quantity" => 5}
      assert %{"stock" => 11, "name" => "Blue mug"} = data(call("restock_product", arguments))

      assert stock_of("mug") == 11
    end

    test "restocks nothing for a quantity that makes no sense, or a product that is not there",
         %{admin: admin, mug: mug} do
      for quantity <- [0, -3] do
        arguments = %{"admin_id" => admin.id, "product_id" => mug.id, "quantity" => quantity}
        assert refused(call("restock_product", arguments)) != ""
      end

      missing = %{"admin_id" => admin.id, "product_id" => Ecto.UUID.generate(), "quantity" => 1}
      assert refused(call("restock_product", missing)) =~ "not_found"

      assert stock_of("mug") == 6
    end

    test "can not restock as another admin", %{ann: ann, mug: mug} do
      arguments = %{"admin_id" => ann.id, "product_id" => mug.id, "quantity" => 5}
      assert refused(call("restock_product", arguments)) =~ "Pass your own id"
      assert stock_of("mug") == 6
    end
  end

  describe "a session that outlives the account's state" do
    test "a user who is gone is refused at once" do
      :persistent_term.put({Policy, :user_id}, Ecto.UUID.generate())
      assert refused(call("list_products")) =~ "no longer exists"
    end

    test "a customer who is promoted gets the admin rights at once, without signing in again" do
      %{ann: ann} = shop!()
      sign_in!(ann)
      assert refused(call("shop_report", %{"admin_id" => ann.id})) =~ "Admins only"

      WebShop.Infrastructure.Repo.query!("UPDATE users SET role = 'admin' WHERE id = $1", [
        Ecto.UUID.dump!(ann.id)
      ])

      assert data(call("me"))["role"] == "admin"
      assert data(call("shop_report", %{"admin_id" => ann.id}))
    end
  end

  describe "mix shop.mcp" do
    test "starts the application without the web server only, and takes --email" do
      on_exit(fn -> Application.delete_env(:web_shop, :start_web) end)
      before = Application.get_all_env(:web_shop)

      assert :ok = Mix.Tasks.Shop.Mcp.prepare(email: "ann@example.com")

      assert Application.get_env(:web_shop, :start_web) == false
      # The poller and the handlers keep running, so the reports are up to date.
      for key <- ~w(start_outbox_poller subscribe_handlers)a,
          do: assert(Application.get_env(:web_shop, key) == before[key])

      assert Application.get_env(:web_shop, :mcp_email) == "ann@example.com"
    end

    test "passes --read-only on to the framework's task, which then refuses every command" do
      assert Mix.Tasks.Shop.Mcp.mcp_args([]) == ["WebShop.Interface.MCP"]
      assert Mix.Tasks.Shop.Mcp.mcp_args(read_only: false) == ["WebShop.Interface.MCP"]

      assert Mix.Tasks.Shop.Mcp.mcp_args(read_only: true) == [
               "WebShop.Interface.MCP",
               "--read-only"
             ]
    end
  end

  # The stock of the product whose name contains `search`, as the shop shows it.
  defp stock_of(search) do
    %{"products" => [%{"stock" => stock}]} = data(call("list_products", %{"search" => search}))
    stock
  end
end
