defmodule WebShop.LiveTest do
  use WebShop.ConnCase

  test "pages need a login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, "/")
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, "/basket")
  end

  test "a customer cannot open the admin pages", %{conn: conn} do
    conn = log_in(conn, register!())
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/products")
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/report")
  end

  test "a logged-in user is sent away from the login page", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = conn |> log_in(register!()) |> live("/login")
  end

  test "logging out: the page has a form that deletes the session, which ends it", %{conn: conn} do
    conn = log_in(conn, register!())
    {:ok, view, _html} = live(conn, "/")

    # A plain form (no JS needed): it posts `_method=delete` to /session.
    assert has_element?(
             view,
             ~s(form#logout-form[action="/session"] input[name="_method"][value="delete"])
           )

    conn = delete(conn, "/session")
    assert redirected_to(conn) == "/login"

    # The cookie is gone: the next request is a guest's.
    assert conn |> recycle() |> get("/") |> redirected_to() == "/login"
  end

  describe "header links" do
    # A live link (`navigate`) is rendered with `data-phx-link`; a plain one (`href`) without.
    # A live navigate across live sessions would be refused with a warning and a reload, so the
    # header links across sessions on purpose.
    defp live_link?(view, path), do: has_element?(view, ~s(a[href="#{path}"][data-phx-link]))

    defp plain_link?(view, path),
      do: has_element?(view, ~s(a[href="#{path}"])) and not live_link?(view, path)

    test "an admin on a shop page: shop links are live, admin links load the page afresh",
         %{conn: conn} do
      {:ok, view, _html} = conn |> log_in(admin!()) |> live("/")

      for path <- ~w(/ /basket /orders), do: assert(live_link?(view, path), path)
      for path <- ~w(/admin/products /admin/report), do: assert(plain_link?(view, path), path)
    end

    test "an admin on an admin page: admin links are live, shop links load the page afresh",
         %{conn: conn} do
      {:ok, view, _html} = conn |> log_in(admin!()) |> live("/admin/report")

      for path <- ~w(/admin/products /admin/report), do: assert(live_link?(view, path), path)
      for path <- ~w(/ /basket /orders), do: assert(plain_link?(view, path), path)
    end

    test "a customer sees only the shop links, all live", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in(register!()) |> live("/basket")

      for path <- ~w(/ /basket /orders), do: assert(live_link?(view, path), path)
      refute has_element?(view, ~s(a[href^="/admin"]))
    end

    test "a guest's links between login and register are live", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/login")
      assert live_link?(view, "/register")

      {:ok, view, _html} = live(conn, "/register")
      assert live_link?(view, "/login")
    end
  end

  describe "login" do
    test "a right password posts to the session, which logs in", %{conn: conn} do
      register!()
      {:ok, view, _html} = live(conn, "/login")

      form =
        form(view, "#login-form",
          user: %{email: "ann@example.com", password: "long-enough-password"}
        )

      render_submit(form)
      conn = follow_trigger_action(form, conn)
      assert redirected_to(conn) == "/"
      assert get_session(conn, :user_id)
    end

    test "a wrong password shows an error", %{conn: conn} do
      register!()
      {:ok, view, _html} = live(conn, "/login")

      html =
        view
        |> form("#login-form", user: %{email: "ann@example.com", password: "nope-nope-nope"})
        |> render_submit()

      assert html =~ "Wrong email or password"
    end

    test "posting to the session directly with a wrong password logs nobody in", %{conn: conn} do
      register!()

      conn =
        post(conn, "/session", %{
          "user" => %{"email" => "ann@example.com", "password" => "bad-password"}
        })

      assert redirected_to(conn) == "/login"
      refute get_session(conn, :user_id)
    end

    test "an admin lands on the report", %{conn: conn} do
      admin!()

      conn =
        post(conn, "/session", %{
          "user" => %{"email" => "admin@example.com", "password" => "long-enough-password"}
        })

      assert redirected_to(conn) == "/admin/report"
    end
  end

  describe "register" do
    test "creates a customer", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/register")
      params = [user: %{name: "New", email: "new@example.com", password: "long-enough-password"}]
      view |> form("#register-form", params) |> render_submit()

      assert {:ok, %{role: :customer}} =
               WebShop.Application.Queries.User.Authenticate.call(%{
                 email: "new@example.com",
                 password: "long-enough-password"
               })
    end

    test "shows what is wrong, and ignores a role in the form data", %{conn: conn} do
      register!()
      {:ok, view, _html} = live(conn, "/register")

      html =
        view
        |> form("#register-form", user: %{name: "X", email: "ann@example.com", password: "short"})
        |> render_submit()

      assert html =~ "is already registered"
      assert html =~ "at least 8 characters"

      render_submit(view, "register", %{
        "user" => %{
          "name" => "Evil",
          "email" => "evil@example.com",
          "password" => "long-enough-password",
          "role" => "admin"
        }
      })

      assert {:ok, %{role: :customer}} =
               WebShop.Application.Queries.User.Authenticate.call(%{
                 email: "evil@example.com",
                 password: "long-enough-password"
               })
    end
  end

  describe "shopping" do
    setup %{conn: conn} do
      customer = register!()
      admin = admin!()
      mug = product!(admin, %{name: "Blue mug", stock: 4})
      %{conn: log_in(conn, customer), customer: customer, mug: mug, admin: admin}
    end

    test "browse, search, add to the basket and place an order", %{conn: conn, mug: mug} do
      {:ok, view, html} = live(conn, "/")
      assert html =~ "Blue mug"

      assert view |> element("form.search") |> render_change(%{search: "zzz"}) =~
               "No products found"

      assert view |> element("form.search") |> render_change(%{search: "blue"}) =~ "Blue mug"

      assert view |> element("#product-#{mug.id} button", "Add to basket") |> render_click() =~
               "Added to your basket"

      {:ok, view, html} = live(conn, "/basket")
      assert html =~ "Blue mug"
      assert html =~ "$12.50"

      {:ok, _view, html} =
        view
        |> element("button", "Place order")
        |> render_click()
        |> follow_redirect(conn, "/orders")

      assert html =~ "Thank you"
      assert html =~ "Blue mug"
    end

    test "an out-of-stock product shows as such and its button is disabled", %{
      conn: conn,
      admin: admin
    } do
      empty = product!(admin, %{name: "Gone", stock: 0})
      {:ok, view, html} = live(conn, "/")
      assert html =~ "Out of stock"
      assert has_element?(view, "#product-#{empty.id} button[disabled]")
    end

    test "checkout failure is shown", %{conn: conn, customer: customer, mug: mug} do
      add_to_basket!(customer, mug, 4)
      {:ok, view, _html} = live(conn, "/basket")
      other = register!("other@example.com")
      add_to_basket!(other, mug, 4)
      {:ok, _} = WebShop.Application.Commands.Basket.CheckOut.call(%{customer_id: other.id})

      assert view |> element("button", "Place order") |> render_click() =~
               "only 0 of Blue mug left"
    end

    test "removing a line empties the basket", %{conn: conn, customer: customer, mug: mug} do
      add_to_basket!(customer, mug)
      {:ok, view, _html} = live(conn, "/basket")
      assert view |> element("button", "Remove") |> render_click() =~ "Your basket is empty"
    end
  end

  describe "admin" do
    setup %{conn: conn} do
      %{conn: log_in(conn, admin!())}
    end

    test "adds a product and restocks it", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/products")

      html =
        view
        |> form("#product-form",
          product: %{name: "Tea", description: "Green", price: "3.5", stock: "7"}
        )
        |> render_submit()

      assert html =~ "Product added"
      assert html =~ "$3.50"

      assert view |> element("button", "+10 stock") |> render_click() =~ ">17<"
    end

    test "shows field errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/products")

      html =
        view
        |> form("#product-form", product: %{name: "Tea", price: "abc", stock: "1"})
        |> render_submit()

      assert html =~ "must look like 12 or 12.50"

      html =
        view
        |> form("#product-form", product: %{name: "", price: "1", stock: "1"})
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end

    test "the report page shows the numbers", %{conn: conn} do
      {:ok, view, html} = live(conn, "/admin/report")
      assert html =~ "Orders today"
      assert html =~ "Pending baskets"
      send(view.pid, :refresh)
      assert render(view) =~ "Last 7 days"
    end
  end
end
