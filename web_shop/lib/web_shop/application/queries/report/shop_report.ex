defmodule WebShop.Application.Queries.Report.ShopReport do
  @moduledoc """
  The admin's numbers: orders and revenue today and over the last week, pending baskets and
  their value, the catalog size and what is nearly sold out. Admins only.

  Sales and baskets come from the `DailySales` and `BasketOverview` read models, so they can
  trail reality by the moment the outbox takes to deliver (a few seconds). Product counts are
  read from the products directly.
  """
  use DDD.Query

  alias WebShop.Application.Authorize
  alias WebShop.Application.Projections.Basket.BasketOverview
  alias WebShop.Application.Projections.Order.DailySales
  alias WebShop.Domain.Product.Repository, as: ProductRepository

  @low_stock 5
  @days 7

  query do
    description "Shop figures: orders and revenue today and per day this week, pending baskets, stock"

    field :admin_id, :uuid, required: true, description: "The acting admin"
  end

  @impl DDD.Query
  def execute(%__MODULE__{admin_id: admin_id}) do
    today = Date.utc_today()
    since = Date.add(today, -(@days - 1))

    with :ok <- Authorize.admin(admin_id),
         {:ok, days} <-
           DailySales.list(filter: [day: {:gte, Date.to_iso8601(since)}], order: [desc: :day]),
         {:ok, pending} <- BasketOverview.list(filter: [item_count: {:gt, 0}]),
         {:ok, products} <- ProductRepository.impl().count(),
         {:ok, low_stock} <- ProductRepository.impl().count(filter: [stock: {:lte, @low_stock}]) do
      by_day = Map.new(days, &{&1.day, &1})

      {:ok,
       %{
         today: figures(by_day, today),
         week: Enum.map(0..(@days - 1), &figures(by_day, Date.add(today, -&1))),
         pending_baskets: length(pending),
         pending_units: pending |> Enum.map(& &1.item_count) |> Enum.sum(),
         pending_value_cents: pending |> Enum.map(& &1.total_cents) |> Enum.sum(),
         products: products,
         low_stock_products: low_stock,
         low_stock_limit: @low_stock
       }}
    end
  end

  defp figures(by_day, date) do
    key = Date.to_iso8601(date)
    row = Map.get(by_day, key, %{})

    %{
      day: date,
      orders: Map.get(row, :orders, 0),
      items_sold: Map.get(row, :items_sold, 0),
      revenue_cents: Map.get(row, :revenue_cents, 0)
    }
  end
end
