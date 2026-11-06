defmodule WebShop.Interface.Web.Admin.ReportLive do
  @moduledoc "The admin's report: orders today, pending baskets and the week. Refreshes by itself."
  use Phoenix.LiveView, layout: {WebShop.Interface.Web.Layouts, :app}

  alias WebShop.Application.Queries.Basket.PendingBaskets
  alias WebShop.Application.Queries.Report.ShopReport
  alias WebShop.Interface.Web.Format

  @refresh_ms 5_000

  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, :refresh)
    {:ok, socket |> assign(page_title: "Report") |> load()}
  end

  def render(assigns) do
    ~H"""
    <h1>Report</h1>
    <p class="muted">Figures are a few seconds behind. Updated every 5 seconds.</p>
    <div class="stats">
      <div class="card stat"><span id="orders-today">{@report.today.orders}</span><small>Orders today</small></div>
      <div class="card stat"><span id="revenue-today">{Format.money(@report.today.revenue_cents)}</span><small>Revenue today</small></div>
      <div class="card stat"><span id="pending-baskets">{@report.pending_baskets}</span><small>Pending baskets</small></div>
      <div class="card stat"><span id="pending-value">{Format.money(@report.pending_value_cents)}</span><small>Value in pending baskets</small></div>
      <div class="card stat"><span id="low-stock">{@report.low_stock_products}</span><small>Products with {@report.low_stock_limit} or fewer left</small></div>
      <div class="card stat"><span>{@report.products}</span><small>Products</small></div>
    </div>

    <h2>Last 7 days</h2>
    <table id="week">
      <thead><tr><th>Day</th><th class="num">Orders</th><th class="num">Units sold</th><th class="num">Revenue</th></tr></thead>
      <tbody>
        <tr :for={day <- @report.week}>
          <td>{Date.to_iso8601(day.day)}</td>
          <td class="num">{day.orders}</td>
          <td class="num">{day.items_sold}</td>
          <td class="num">{Format.money(day.revenue_cents)}</td>
        </tr>
      </tbody>
    </table>

    <h2>Pending baskets</h2>
    <p :if={@pending == []} class="muted">No one has a basket waiting.</p>
    <table :if={@pending != []} id="pending">
      <thead><tr><th>Customer</th><th>Email</th><th class="num">Units</th><th class="num">Value</th></tr></thead>
      <tbody>
        <tr :for={basket <- @pending}>
          <td>{basket.customer}</td><td>{basket.email}</td>
          <td class="num">{basket.item_count}</td><td class="num">{Format.money(basket.total_cents)}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  def handle_info(:refresh, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    admin_id = socket.assigns.current_user.id
    {:ok, report} = ShopReport.call(%{admin_id: admin_id})
    {:ok, pending} = PendingBaskets.call(%{admin_id: admin_id})
    assign(socket, report: report, pending: pending)
  end
end
