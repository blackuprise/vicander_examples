defmodule TodoApp.Application.Queries.TodoList.ListActivity do
  @moduledoc """
  Which lists were active lately, from the `ListStats` read model.

  The numbers come from a projection fed by events, so they can trail the lists by the moment
  the outbox takes to deliver. A rule that depends on them must read the aggregate instead.
  """
  use DDD.Query

  alias TodoApp.Application.Projections.TodoList.ListStats

  @max_page_size 100

  query do
    description "The most recently active todo lists first, with how many items were added and completed " <>
                  "in each. Slightly behind the lists themselves"

    field :page, :integer, default: 1, description: "Which page, starting at 1"
    field :page_size, :integer, default: 20, description: "Lists per page (at most 100)"
  end

  @impl DDD.Query
  def execute(%__MODULE__{page: page, page_size: page_size}) do
    options = [
      order: [desc: :last_activity_at],
      page: page,
      page_size: min(page_size, @max_page_size)
    ]

    with {:ok, page} <- ListStats.page(options) do
      {:ok,
       %{
         lists:
           Enum.map(
             page.entries,
             &Map.take(&1, [:list_id, :items_added, :items_completed, :last_activity_at])
           ),
         page: page.page,
         page_size: page.page_size,
         total_lists: page.total_entries,
         total_pages: page.total_pages
       }}
    end
  end
end
