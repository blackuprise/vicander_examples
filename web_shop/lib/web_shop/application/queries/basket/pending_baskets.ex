defmodule WebShop.Application.Queries.Basket.PendingBaskets do
  @moduledoc "The baskets that hold something and were not checked out, biggest first. Admins only."
  use DDD.Query

  alias WebShop.Application.Authorize
  alias WebShop.Application.Projections.Basket.BasketOverview
  alias WebShop.Domain.User.Repository, as: UserRepository

  query do
    description "Pending baskets with the customer, units and value (admin only; slightly behind)"

    field :admin_id, :uuid, required: true, description: "The acting admin"
    field :limit, :integer, default: 20, description: "How many baskets at most"
  end

  @impl DDD.Query
  def execute(%__MODULE__{admin_id: admin_id, limit: limit}) do
    with :ok <- Authorize.admin(admin_id),
         {:ok, rows} <-
           BasketOverview.list(
             filter: [item_count: {:gt, 0}],
             order: [desc: :total_cents],
             limit: min(limit, 100)
           ),
         {:ok, users} <-
           UserRepository.impl().list(filter: [id: {:in, Enum.map(rows, & &1.customer_id)}]) do
      names = Map.new(users, &{&1.id, &1})

      {:ok,
       for row <- rows do
         user = Map.get(names, row.customer_id)

         %{
           basket_id: row.basket_id,
           customer: user && user.name,
           email: user && user.email,
           item_count: row.item_count,
           total_cents: row.total_cents
         }
       end}
    end
  end
end
