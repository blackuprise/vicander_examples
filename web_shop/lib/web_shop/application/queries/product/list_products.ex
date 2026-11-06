defmodule WebShop.Application.Queries.Product.ListProducts do
  @moduledoc "Browse the catalog by name, one page at a time, optionally filtered by a search text."
  use DDD.Query

  alias WebShop.Domain.Product.Repository, as: ProductRepository

  @max_page_size 100

  query do
    description "The products by name, one page at a time; `search` matches part of the name"

    field :search, :string, default: nil, description: "Part of a product name"
    field :page, :integer, default: 1, description: "Which page, starting at 1"
    field :page_size, :integer, default: 12, description: "Products per page (at most 100)"
  end

  @impl DDD.Query
  def execute(%__MODULE__{search: search, page: page, page_size: page_size}) do
    options = [
      filter: filter(search),
      order: [asc: :name],
      page: page,
      page_size: min(page_size, @max_page_size)
    ]

    with {:ok, result} <- ProductRepository.impl().page(options) do
      {:ok,
       %{
         products:
           Enum.map(
             result.entries,
             &Map.take(&1, [:id, :name, :description, :price_cents, :stock])
           ),
         page: result.page,
         total_pages: result.total_pages,
         total_products: result.total_entries
       }}
    end
  end

  defp filter(search) when is_binary(search) do
    case String.trim(search) do
      "" -> []
      text -> [name: {:ilike, "%" <> escape(text) <> "%"}]
    end
  end

  defp filter(_), do: []

  # `%`, `_` and `\` are wildcards in LIKE: search for them literally.
  defp escape(text), do: String.replace(text, ~r/[\\%_]/, "\\\\\\0")
end
