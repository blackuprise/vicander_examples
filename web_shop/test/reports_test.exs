defmodule WebShop.ReportsTest do
  use WebShop.DataCase

  @moduletag :capture_log

  alias DDD.Outbox.Poller
  alias WebShop.Application.{Commands, Queries}
  alias WebShop.Application.Projections.Basket.BasketOverview
  alias WebShop.Application.Projections.Order.DailySales

  setup do
    start_supervised!({Poller, repo: Repo, interval_ms: 600_000})
    DailySales.subscribe()
    BasketOverview.subscribe()

    on_exit(fn ->
      DailySales.unsubscribe()
      BasketOverview.unsubscribe()
    end)

    admin = admin!()

    %{
      admin: admin,
      mug: product!(admin, %{stock: 20}),
      pot: product!(admin, %{name: "Pot", price_cents: 4000, stock: 3})
    }
  end

  defp report(admin) do
    {:ok, _} = Poller.poll_now()
    {:ok, report} = Queries.Report.ShopReport.call(%{admin_id: admin.id})
    report
  end

  test "an empty shop reports zeros", %{admin: admin} do
    report = report(admin)
    assert %{orders: 0, revenue_cents: 0} = report.today
    assert report.pending_baskets == 0
    assert report.products == 2
    assert length(report.week) == 7
  end

  test "counts orders and revenue today, and pending baskets", %{admin: admin, mug: mug, pot: pot} do
    ann = register!("ann@example.com")
    bob = register!("bob@example.com")
    cy = register!("cy@example.com")

    # Ann orders twice, Bob has a basket waiting, Cy filled a basket and emptied it again.
    add_to_basket!(ann, mug, 2)
    {:ok, _} = Commands.Basket.CheckOut.call(%{customer_id: ann.id})
    add_to_basket!(ann, pot, 1)
    {:ok, _} = Commands.Basket.CheckOut.call(%{customer_id: ann.id})
    add_to_basket!(bob, mug, 3)
    add_to_basket!(cy, pot, 1)
    {:ok, _} = Commands.Basket.RemoveFromBasket.call(%{customer_id: cy.id, product_id: pot.id})

    report = report(admin)

    assert report.today.orders == 2
    assert report.today.items_sold == 3
    assert report.today.revenue_cents == 2 * 1250 + 4000
    assert report.pending_baskets == 1
    assert report.pending_units == 3
    assert report.pending_value_cents == 3 * 1250
    assert report.low_stock_products == 1

    assert {:ok, [%{customer: "Ann", email: "bob@example.com", item_count: 3, total_cents: 3750}]} =
             Queries.Basket.PendingBaskets.call(%{admin_id: admin.id})
  end

  test "delivering an event twice does not count it twice", %{admin: admin, mug: mug} do
    ann = register!()
    add_to_basket!(ann, mug)
    {:ok, _} = Commands.Basket.CheckOut.call(%{customer_id: ann.id})

    report(admin)
    assert report(admin).today.orders == 1
  end
end
