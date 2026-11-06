defmodule WebShop.Interface.Web.Router do
  @moduledoc "Routes. Every page needs a login; `/admin/*` needs an admin."
  use Phoenix.Router
  import Phoenix.LiveView.Router

  alias WebShop.Interface.Web.{Auth, Layouts}

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", WebShop.Interface.Web do
    pipe_through(:browser)

    post("/session", SessionController, :create)
    delete("/session", SessionController, :delete)

    live_session :guest, on_mount: [{Auth, :redirect_if_logged_in}], layout: {Layouts, :app} do
      live("/login", LoginLive)
      live("/register", RegisterLive)
    end

    live_session :customer, on_mount: [{Auth, :require_user}], layout: {Layouts, :app} do
      live("/", ShopLive)
      live("/basket", BasketLive)
      live("/orders", OrdersLive)
    end

    live_session :admin, on_mount: [{Auth, :require_admin}], layout: {Layouts, :app} do
      live("/admin/products", Admin.ProductsLive)
      live("/admin/report", Admin.ReportLive)
    end
  end
end
