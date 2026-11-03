defmodule TodoApp.Application.Queries.TodoList.SearchLists do
  @moduledoc """
  Lists by part of their name, optionally of one owner, continued from a cursor.

  A cursor ("slice") page costs the same however far you go and doesn't shift when lists are
  added meanwhile, which is what a client that keeps asking for "more" wants.
  """
  use DDD.Query

  alias TodoApp.Domain.TodoList.Repository, as: TodoListRepository

  @max_limit 100

  query do
    description "Search todo lists by part of their name, A to Z, optionally only a user's. Returns up to " <>
                  "`limit` lists and a `next_cursor` to pass as `after` for the following ones"

    field :name_contains, :string, description: "Part of the name, in any case"
    field :owner_id, :uuid, description: "Only the lists of this user"
    field :limit, :integer, default: 20, description: "How many lists at most (up to 100)"
    field :after, :string, description: "The `next_cursor` of the previous result"
  end

  @impl DDD.Query
  def execute(%__MODULE__{} = query) do
    options = [
      filter: filter(query),
      order: [asc: :name],
      limit: min(query.limit, @max_limit),
      after: query.after
    ]

    with {:ok, slice} <- TodoListRepository.impl().slice(options) do
      {:ok,
       %{
         lists: Enum.map(slice.entries, &%{id: &1.id, name: &1.name, owner_id: &1.owner_id}),
         next_cursor: slice.next_cursor
       }}
    end
  end

  defp filter(query) do
    Enum.reject(
      [
        query.owner_id && {:owner_id, query.owner_id},
        query.name_contains && {:name, {:ilike, "%" <> escape_like(query.name_contains) <> "%"}}
      ],
      &is_nil/1
    )
  end

  # `%` and `_` in what the user typed are text, not wildcards.
  defp escape_like(text), do: String.replace(text, ~r/[\\%_]/, "\\\\\\0")
end
