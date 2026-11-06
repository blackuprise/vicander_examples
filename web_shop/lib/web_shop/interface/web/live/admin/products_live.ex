defmodule WebShop.Interface.Web.Admin.ProductsLive do
  @moduledoc "Admins add products and restock them. The commands check the role again themselves."
  use Phoenix.LiveView, layout: {WebShop.Interface.Web.Layouts, :app}

  alias WebShop.Application.Commands.Product.{AddProduct, RestockProduct}
  alias WebShop.Application.Queries.Product.ListProducts
  alias WebShop.Interface.Web.Format

  @blank %{"name" => "", "description" => "", "price" => "", "stock" => "0"}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Products", errors: %{}, form: to_form(@blank, as: :product))
     |> load()}
  end

  def render(assigns) do
    ~H"""
    <h1>Products</h1>
    <section class="card">
      <h2>Add a product</h2>
      <.form for={@form} id="product-form" phx-submit="add">
        <label>Name <input type="text" name={@form[:name].name} value={@form[:name].value} required /></label>
        <p :for={m <- @errors[:name] || []} class="field-error">{m}</p>
        <label>Description <input type="text" name={@form[:description].name} value={@form[:description].value} /></label>
        <label>Price in dollars (e.g. 12.50) <input type="text" inputmode="decimal" name={@form[:price].name} value={@form[:price].value} required /></label>
        <p :for={m <- (@errors[:price] || []) ++ (@errors[:price_cents] || [])} class="field-error">{m}</p>
        <label>Stock <input type="number" min="0" name={@form[:stock].name} value={@form[:stock].value} required /></label>
        <p :for={m <- @errors[:stock] || []} class="field-error">{m}</p>
        <button type="submit">Add product</button>
      </.form>
    </section>
    <table>
      <thead><tr><th>Name</th><th class="num">Price</th><th class="num">Stock</th><th></th></tr></thead>
      <tbody>
        <tr :for={product <- @products} id={"product-#{product.id}"}>
          <td>{product.name}</td>
          <td class="num">{Format.money(product.price_cents)}</td>
          <td class="num">{product.stock}</td>
          <td><button class="ghost" phx-click="restock" phx-value-id={product.id}>+10 stock</button></td>
        </tr>
      </tbody>
    </table>
    """
  end

  def handle_event("add", %{"product" => params}, socket) do
    with {:ok, cents} <-
           parse(Format.parse_cents(params["price"]), :price, "must look like 12 or 12.50"),
         {:ok, stock} <-
           parse(Format.parse_int(params["stock"]), :stock, "must be a whole number"),
         {:ok, _product} <-
           AddProduct.call(%{
             admin_id: socket.assigns.current_user.id,
             name: params["name"],
             description: params["description"],
             price_cents: cents,
             stock: stock
           }) do
      {:noreply,
       socket
       |> put_flash(:info, "Product added.")
       |> assign(errors: %{}, form: to_form(@blank, as: :product))
       |> load()}
    else
      {:field_error, field, message} ->
        {:noreply,
         assign(socket, errors: %{field => [message]}, form: to_form(params, as: :product))}

      {:error, %DDD.Error{code: :forbidden} = error} ->
        {:noreply, put_flash(socket, :error, Format.error(error))}

      {:error, error} ->
        {:noreply,
         assign(socket, errors: Format.field_errors(error), form: to_form(params, as: :product))}
    end
  end

  def handle_event("restock", %{"id" => id}, socket) do
    case RestockProduct.call(%{
           admin_id: socket.assigns.current_user.id,
           product_id: id,
           quantity: 10
         }) do
      {:ok, _} -> {:noreply, load(socket)}
      {:error, error} -> {:noreply, put_flash(socket, :error, Format.error(error))}
    end
  end

  defp parse({:ok, value}, _field, _message), do: {:ok, value}
  defp parse(:error, field, message), do: {:field_error, field, message}

  defp load(socket) do
    {:ok, result} = ListProducts.call(%{page_size: 100})
    assign(socket, products: result.products)
  end
end
