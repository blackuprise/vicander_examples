defmodule WebShop.Interface.Web.OrdersLive do
  @moduledoc "The customer's past orders."
  use Phoenix.LiveView, layout: {WebShop.Interface.Web.Layouts, :app}

  alias WebShop.Application.Queries.Order.OrdersOfCustomer
  alias WebShop.Interface.Web.Format

  def mount(_params, _session, socket) do
    {:ok, orders} = OrdersOfCustomer.call(%{customer_id: socket.assigns.current_user.id})
    {:ok, assign(socket, page_title: "My orders", orders: orders.orders)}
  end

  def render(assigns) do
    ~H"""
    <h1>My orders</h1>
    <p :if={@orders == []} class="muted">You have not ordered anything yet.</p>
    <article :for={order <- @orders} class="card" id={"order-#{order.id}"}>
      <h2>{Format.datetime(order.placed_at)} <span class="price">{Format.money(order.total_cents)}</span></h2>
      <ul>
        <li :for={line <- order.lines}>{line.quantity} × {line.name} ({Format.money(line.unit_price_cents)} each)</li>
      </ul>
    </article>
    """
  end
end
