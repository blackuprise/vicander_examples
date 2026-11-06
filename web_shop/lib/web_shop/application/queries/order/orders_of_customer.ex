defmodule WebShop.Application.Queries.Order.OrdersOfCustomer do
  @moduledoc "A customer's orders, newest first."
  use DDD.Query

  alias WebShop.Domain.Order.Repository, as: OrderRepository

  query do
    description "The orders a customer placed, newest first, with their lines"

    field :customer_id, :uuid, required: true, description: "The customer"
    field :page, :integer, default: 1, description: "Which page, starting at 1"
  end

  @impl DDD.Query
  def execute(%__MODULE__{customer_id: customer_id, page: page}) do
    with {:ok, result} <-
           OrderRepository.impl().page(
             filter: [customer_id: customer_id],
             order: [desc: :placed_at],
             page: page,
             page_size: 10
           ) do
      {:ok,
       %{
         orders: Enum.map(result.entries, &summary/1),
         page: result.page,
         total_pages: result.total_pages
       }}
    end
  end

  defp summary(order) do
    %{
      id: order.id,
      placed_at: order.placed_at,
      total_cents: order.total_cents,
      lines: Enum.map(order.lines, &Map.take(&1, [:name, :unit_price_cents, :quantity]))
    }
  end
end
