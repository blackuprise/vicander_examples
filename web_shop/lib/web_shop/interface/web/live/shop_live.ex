defmodule WebShop.Interface.Web.ShopLive do
  @moduledoc "Browse and search the catalog and put products in the basket."
  use Phoenix.LiveView, layout: {WebShop.Interface.Web.Layouts, :app}

  alias WebShop.Application.Commands.Basket.AddToBasket
  alias WebShop.Application.Queries.Product.ListProducts
  alias WebShop.Interface.Web.{Auth, Format}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Shop", search: "", page: 1) |> load()}
  end

  def render(assigns) do
    ~H"""
    <h1>Shop</h1>
    <form id="search-form" phx-change="search" phx-submit="search" class="search">
      <input type="search" name="search" value={@search} placeholder="Search products" phx-debounce="300" autocomplete="off" />
    </form>
    <p :if={@products == []} class="muted">No products found.</p>
    <div class="grid">
      <article :for={product <- @products} class="card product" id={"product-#{product.id}"}>
        <h2>{product.name}</h2>
        <p class="muted">{product.description}</p>
        <p class="price">{Format.money(product.price_cents)}</p>
        <p class={["stock", product.stock <= 5 && "low"]}>
          {if product.stock == 0, do: "Out of stock", else: "#{product.stock} in stock"}
        </p>
        <button phx-click="add" phx-value-id={product.id} disabled={product.stock == 0}>Add to basket</button>
      </article>
    </div>
    <nav :if={@total_pages > 1} class="pager">
      <button :if={@page > 1} phx-click="page" phx-value-page={@page - 1} class="ghost">Previous</button>
      <span>Page {@page} of {@total_pages}</span>
      <button :if={@page < @total_pages} phx-click="page" phx-value-page={@page + 1} class="ghost">Next</button>
    </nav>
    """
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(search: search, page: 1) |> load()}
  end

  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, socket |> assign(page: String.to_integer(page)) |> load()}
  end

  def handle_event("add", %{"id" => product_id}, socket) do
    user = socket.assigns.current_user

    case AddToBasket.call(%{customer_id: user.id, product_id: product_id, quantity: 1}) do
      {:ok, _basket} ->
        {:noreply,
         socket
         |> assign(basket_quantity: Auth.basket_quantity(user))
         |> put_flash(:info, "Added to your basket.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Format.error(error))}
    end
  end

  defp load(socket) do
    {:ok, result} = ListProducts.call(%{search: socket.assigns.search, page: socket.assigns.page})
    assign(socket, products: result.products, total_pages: max(result.total_pages, 1))
  end
end
