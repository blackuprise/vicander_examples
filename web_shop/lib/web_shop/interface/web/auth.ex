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

  @doc """
  Where to go after logging in, if it is somewhere the login may send you back to: only an
  authorization request of this shop (`/oauth/authorize?...`), which is how an app that sent you
  to log in gets you back to the consent page. Anything else is nil, so `return_to` can never be
  turned into a redirect to another site.
  """
  @spec safe_return_to(term()) :: String.t() | nil
  def safe_return_to("/oauth/authorize?" <> _ = path) do
    if String.match?(path, ~r/[\\\x00-\x1f\x7f]/), do: nil, else: path
  end

  def safe_return_to(_other), do: nil

  # Each hook also records the live session its pages belong to (`:live_session`, see the
  # router), because the header must know it: a live `navigate` works inside one session only,
  # and a link to a page of another one has to be a plain `href` (a fresh page load).
  def on_mount(:redirect_if_logged_in, _params, session, socket) do
    case current_user(session) do
      nil -> {:cont, socket |> mount_user(nil) |> assign(:live_session, :guest)}
      _user -> {:halt, redirect(socket, to: "/")}
    end
  end

  def on_mount(:require_user, _params, session, socket) do
    case current_user(session) do
      nil ->
        {:halt, socket |> put_flash(:error, "Please log in.") |> redirect(to: "/login")}

      user ->
        {:cont, socket |> mount_user(user) |> assign(:live_session, :customer)}
    end
  end

  def on_mount(:require_admin, params, session, socket) do
    case on_mount(:require_user, params, session, socket) do
      {:cont, %{assigns: %{current_user: %{role: :admin}}} = socket} ->
        {:cont, assign(socket, :live_session, :admin)}

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
