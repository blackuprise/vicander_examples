defmodule WebShop.Interface.Web.BasketLive do
  @moduledoc "The customer's basket: remove lines and check out."
  use Phoenix.LiveView, layout: {WebShop.Interface.Web.Layouts, :app}

  alias WebShop.Application.Commands.Basket.{CheckOut, RemoveFromBasket}
  alias WebShop.Application.Queries.Basket.ViewBasket
  alias WebShop.Interface.Web.Format

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Basket") |> load()}
  end

  def render(assigns) do
    ~H"""
    <h1>Your basket</h1>
    <%= if @basket.items == [] do %>
      <p class="muted">Your basket is empty. <.link navigate="/">Browse the shop</.link>.</p>
    <% else %>
      <table>
        <thead>
          <tr><th>Product</th><th class="num">Price</th><th class="num">Qty</th><th class="num">Total</th><th></th></tr>
        </thead>
        <tbody>
          <tr :for={item <- @basket.items} id={"line-#{item.product_id}"}>
            <td>{item.name}</td>
            <td class="num">{Format.money(item.unit_price_cents)}</td>
            <td class="num">{item.quantity}</td>
            <td class="num">{Format.money(item.line_cents)}</td>
            <td><button class="ghost" phx-click="remove" phx-value-id={item.product_id}>Remove</button></td>
          </tr>
        </tbody>
        <tfoot>
          <tr><th colspan="3">Total</th><th class="num">{Format.money(@basket.total_cents)}</th><td></td></tr>
        </tfoot>
      </table>
      <button phx-click="check_out" data-confirm="Place this order?">Place order</button>
    <% end %>
    """
  end

  def handle_event("remove", %{"id" => product_id}, socket) do
    case RemoveFromBasket.call(%{
           customer_id: socket.assigns.current_user.id,
           product_id: product_id
         }) do
      {:ok, _} -> {:noreply, load(socket)}
      {:error, error} -> {:noreply, put_flash(socket, :error, Format.error(error))}
    end
  end

  def handle_event("check_out", _params, socket) do
    case CheckOut.call(%{customer_id: socket.assigns.current_user.id}) do
      {:ok, _order} ->
        {:noreply,
         socket
         |> put_flash(:info, "Thank you! Your order was placed.")
         |> push_navigate(to: "/orders")}

      {:error, error} ->
        {:noreply, socket |> put_flash(:error, Format.error(error)) |> load()}
    end
  end

  defp load(socket) do
    {:ok, basket} = ViewBasket.call(%{customer_id: socket.assigns.current_user.id})
    assign(socket, basket: basket, basket_quantity: basket.quantity)
  end
end
