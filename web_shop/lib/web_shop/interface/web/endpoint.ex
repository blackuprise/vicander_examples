defmodule WebShop.Interface.Web.Endpoint do
  @moduledoc "The Phoenix endpoint. JS comes straight from the `phoenix` deps: there is no asset build."
  use Phoenix.Endpoint, otp_app: :web_shop

  @session_options [
    store: :cookie,
    key: "_web_shop_key",
    signing_salt: "web-shop-session-salt",
    same_site: "Lax",
    http_only: true
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Static, at: "/", from: :web_shop, gzip: false, only: ~w(app.css app.js favicon.svg))
  plug(Plug.Static, at: "/js/phoenix", from: {:phoenix, "priv/static"}, only: ~w(phoenix.min.js))

  plug(Plug.Static,
    at: "/js/live_view",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.min.js)
  )

  plug(Plug.RequestId)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(WebShop.Interface.Web.Router)
end
