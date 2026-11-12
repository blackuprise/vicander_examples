defmodule WebShop.Interface.Web.SessionController do
  @moduledoc """
  Starts and ends the cookie session. The login and register LiveViews check the credentials,
  then submit the form here (`phx-trigger-action`), because a LiveView cannot set a cookie. The
  credentials are checked again here, so posting to this route directly gets no further.
  """
  use Phoenix.Controller, formats: [:html]
  import Plug.Conn

  alias WebShop.Application.Queries.User.Authenticate
  alias WebShop.Interface.Web.Auth

  def create(conn, %{"user" => %{"email" => email, "password" => password}} = params)
      when is_binary(email) and is_binary(password) do
    case Authenticate.call(%{email: email, password: password}) do
      {:ok, user} ->
        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> put_session(:user_id, user.id)
        |> redirect(to: after_login(user, params["return_to"]))

      {:error, _} ->
        conn |> put_flash(:error, "Wrong email or password") |> redirect(to: "/login")
    end
  end

  def create(conn, _params), do: redirect(conn, to: "/login")

  # Back to the app that sent the user here to log in, if that is what `return_to` is; else home.
  defp after_login(user, return_to) do
    Auth.safe_return_to(return_to) ||
      if user.role == :admin, do: "/admin/report", else: "/"
  end

  def delete(conn, _params) do
    conn |> configure_session(drop: true) |> redirect(to: "/login")
  end
end
