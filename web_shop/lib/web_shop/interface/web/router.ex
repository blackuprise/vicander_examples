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

  # OAuth and MCP are for programs: they send tokens, not cookies, so there is no session and no
  # CSRF token here. (The OAuth routes answer 404 when an external server does the authorizing.)
  scope "/", WebShop.Interface.Web do
    get("/.well-known/oauth-protected-resource/mcp", OAuthController, :resource_metadata)
    get("/.well-known/oauth-authorization-server", OAuthController, :server_metadata)
    get("/oauth/jwks", OAuthController, :jwks)
    post("/oauth/register", OAuthController, :register)
    post("/oauth/token", OAuthController, :token)
  end

  # The MCP endpoint (no alias: the plug is the framework's). A request needs a bearer token; one
  # without gets the `401` that says where to log in.
  scope "/" do
    forward("/mcp", DDD.MCP.HTTP,
      server: WebShop.Interface.MCP,
      authenticate: &WebShop.Interface.MCP.Auth.authenticate/1,
      authorize_request: &WebShop.Interface.MCP.Policy.required_scope/2,
      resource_metadata: &WebShop.Application.OAuth.Endpoints.resource_metadata_url/0,
      allowed_origins: []
    )
  end

  scope "/", WebShop.Interface.Web do
    pipe_through(:browser)

    # The user's part of the OAuth flow: the consent page, and the decision.
    get("/oauth/authorize", OAuthController, :authorize)
    post("/oauth/authorize", OAuthController, :decide)

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
