defmodule WebShop.Interface.Web.Auth do
  @moduledoc """
  Login state. The cookie session holds only the user's id; every page load (and every LiveView
  mount) asks the application for the user, so a deleted user or a changed role takes effect at
  once. `on_mount` hooks guard the LiveView sessions in the router.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2, put_flash: 3]

  alias WebShop.Application.Queries

  @doc "The user (a map) for the id kept in the session, or nil."
  def current_user(%{"user_id" => id}) when is_binary(id) do
    case Queries.User.GetUser.call(%{id: id}) do
      {:ok, user} -> user
      _ -> nil
    end
  end

  def current_user(_session), do: nil

  def on_mount(:redirect_if_logged_in, _params, session, socket) do
    case current_user(session) do
      nil -> {:cont, mount_user(socket, nil)}
      _user -> {:halt, redirect(socket, to: "/")}
    end
  end

  def on_mount(:require_user, _params, session, socket) do
    case current_user(session) do
      nil -> {:halt, socket |> put_flash(:error, "Please log in.") |> redirect(to: "/login")}
      user -> {:cont, mount_user(socket, user)}
    end
  end

  def on_mount(:require_admin, params, session, socket) do
    case on_mount(:require_user, params, session, socket) do
      {:cont, %{assigns: %{current_user: %{role: :admin}}} = socket} ->
        {:cont, socket}

      {:cont, socket} ->
        {:halt, socket |> put_flash(:error, "Admins only.") |> redirect(to: "/")}

      halt ->
        halt
    end
  end

  defp mount_user(socket, user) do
    socket
    |> assign(:current_user, user)
    |> assign(:basket_quantity, basket_quantity(user))
  end

  @doc "The number of units in the user's basket (for the header)."
  def basket_quantity(%{id: id}) do
    case Queries.Basket.ViewBasket.call(%{customer_id: id}) do
      {:ok, %{quantity: quantity}} -> quantity
      _ -> 0
    end
  end

  def basket_quantity(_), do: 0
end
