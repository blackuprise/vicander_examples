defmodule WebShop.Domain.Order do
  @moduledoc """
  Aggregate: a placed order. It is a record of the purchase (lines and prices as they were at
  checkout) and never changes afterwards.
  """
  use DDD.Aggregate

  alias WebShop.Domain.Order.{Events, OrderLine}

  aggregate do
    description "A placed order"

    identity :id, :uuid
    field :customer_id, {:ref, WebShop.Domain.User}, required: true, description: "The buyer"
    field :lines, {:list, OrderLine}, default: [], description: "What was bought"
    field :total_cents, :integer, required: true, description: "The total price in cents"
    field :placed_at, :datetime_usec, required: true, description: "When it was placed (UTC)"
  end

  @doc "Place an order for `lines` (a list of `OrderLine`s). Emits `OrderPlaced`."
  @spec place(binary(), [struct()]) :: {:ok, struct()} | {:error, DDD.Error.t()}
  def place(customer_id, lines) do
    now = DateTime.utc_now()
    total = lines |> Enum.map(&OrderLine.line_cents/1) |> Enum.sum()

    with {:ok, order} <-
           new(customer_id: customer_id, lines: lines, total_cents: total, placed_at: now) do
      {:ok,
       emit_event(
         order,
         Events.OrderPlaced.new(%{
           customer_id: customer_id,
           total_cents: total,
           items: Enum.sum(Enum.map(lines, & &1.quantity)),
           day: now |> DateTime.to_date() |> Date.to_iso8601()
         })
       )}
    end
  end
end
