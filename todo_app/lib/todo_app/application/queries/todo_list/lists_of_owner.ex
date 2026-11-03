defmodule TodoApp.Application.Queries.TodoList.ListsOfOwner do
  @moduledoc "A user's lists, one numbered page at a time, with how many items are open and done."
  use DDD.Query

  alias TodoApp.Domain.TodoList.Repository, as: TodoListRepository

  @max_page_size 100

  query do
    description "The todo lists of a user by name, one page at a time, with the number of open and done " <>
                  "items in each"

    field :owner_id, :uuid, required: true, description: "The id of the user"
    field :page, :integer, default: 1, description: "Which page, starting at 1"
    field :page_size, :integer, default: 20, description: "Lists per page (at most 100)"
  end

  @impl DDD.Query
  def execute(%__MODULE__{owner_id: owner_id, page: page, page_size: page_size}) do
    options = [
      filter: [owner_id: owner_id],
      order: [asc: :name],
      page: page,
      page_size: min(page_size, @max_page_size)
    ]

    with {:ok, page} <- TodoListRepository.impl().page(options) do
      {:ok,
       %{
         lists: Enum.map(page.entries, &summary/1),
         page: page.page,
         page_size: page.page_size,
         total_lists: page.total_entries,
         total_pages: page.total_pages
       }}
    end
  end

  defp summary(list) do
    %{
      id: list.id,
      name: list.name,
      open: Enum.count(list.items, &(&1.status == :open)),
      done: Enum.count(list.items, &(&1.status == :done))
    }
  end
end
