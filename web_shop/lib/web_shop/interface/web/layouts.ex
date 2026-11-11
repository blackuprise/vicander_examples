defmodule WebShop.Interface.Web.Layouts do
  @moduledoc "The page shell: `root/1` is the HTML document, `app/1` the header and flash around every page."
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <.live_title default="Web Shop">{assigns[:page_title]}</.live_title>
        <link rel="stylesheet" href="/app.css" />
        <script defer src="/js/phoenix/phoenix.min.js">
        </script>
        <script defer src="/js/live_view/phoenix_live_view.min.js">
        </script>
        <script defer src="/app.js">
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  # The attributes of a link to `path`, a page of the live session `session` (see the router).
  # A live `navigate` keeps the connection and works only inside one live session; to a page of
  # another session LiveView would log a warning and reload the page anyway, so that link is a
  # plain `href`, which loads it afresh on purpose. `assigns[:live_session]` is set by the
  # `on_mount` hooks in `WebShop.Interface.Web.Auth`.
  defp link_to(assigns, session, path) do
    if assigns[:live_session] == session, do: [navigate: path], else: [href: path]
  end

  def app(assigns) do
    ~H"""
    <header class="topbar">
      <a class="brand" href="/">Web Shop</a>
      <nav :if={@current_user}>
        <.link {link_to(assigns, :customer, "/")}>Shop</.link>
        <.link {link_to(assigns, :customer, "/basket")}>
          Basket <span :if={@basket_quantity > 0} class="badge">{@basket_quantity}</span>
        </.link>
        <.link {link_to(assigns, :customer, "/orders")}>My orders</.link>
        <.link :if={@current_user.role == :admin} {link_to(assigns, :admin, "/admin/products")}>
          Products
        </.link>
        <.link :if={@current_user.role == :admin} {link_to(assigns, :admin, "/admin/report")}>
          Report
        </.link>
      </nav>
      <div class="who">
        <%= if @current_user do %>
          <span>{@current_user.name}<small :if={@current_user.role == :admin}> (admin)</small></span>
          <.form for={%{}} action="/session" method="delete" id="logout-form">
            <button type="submit" class="ghost">Log out</button>
          </.form>
        <% else %>
          <.link {link_to(assigns, :guest, "/login")}>Log in</.link>
          <.link {link_to(assigns, :guest, "/register")} class="button">Register</.link>
        <% end %>
      </div>
    </header>
    <main>
      <p :if={msg = Phoenix.Flash.get(@flash, :info)} class="flash info" phx-click="lv:clear-flash" phx-value-key="info" role="status">{msg}</p>
      <p :if={msg = Phoenix.Flash.get(@flash, :error)} class="flash error" phx-click="lv:clear-flash" phx-value-key="error" role="alert">{msg}</p>
      {@inner_content}
    </main>
    """
  end
end
