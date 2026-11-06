defmodule WebShop.Interface.Web.SessionController do
  @moduledoc """
  Starts and ends the cookie session. The login and register LiveViews check the credentials,
  then submit the form here (`phx-trigger-action`), because a LiveView cannot set a cookie. The
  credentials are checked again here, so posting to this route directly gets no further.
  """
  use Phoenix.Controller, formats: [:html]
  import Plug.Conn

  alias WebShop.Application.Queries.User.Authenticate

  def create(conn, %{"user" => %{"email" => email, "password" => password}})
      when is_binary(email) and is_binary(password) do
    case Authenticate.call(%{email: email, password: password}) do
      {:ok, user} ->
        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> put_session(:user_id, user.id)
        |> redirect(to: if(user.role == :admin, do: "/admin/report", else: "/"))

      {:error, _} ->
        conn |> put_flash(:error, "Wrong email or password") |> redirect(to: "/login")
    end
  end

  def create(conn, _params), do: redirect(conn, to: "/login")

  def delete(conn, _params) do
    conn |> configure_session(drop: true) |> redirect(to: "/login")
  end
end
