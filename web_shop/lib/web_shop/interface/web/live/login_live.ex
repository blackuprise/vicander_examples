defmodule WebShop.Interface.Web.LoginLive do
  @moduledoc "The login form. The credentials are checked here for a good message, then posted to the session controller."
  use Phoenix.LiveView, layout: {WebShop.Interface.Web.Layouts, :app}

  alias WebShop.Application.Queries.User.Authenticate

  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Log in",
       trigger_action: false,
       return_to: WebShop.Interface.Web.Auth.safe_return_to(params["return_to"])
     )
     |> assign(form: to_form(%{"email" => "", "password" => ""}, as: :user))}
  end

  def render(assigns) do
    ~H"""
    <section class="card narrow">
      <h1>Log in</h1>
      <.form for={@form} id="login-form" action="/session" phx-submit="login" phx-trigger-action={@trigger_action}>
        <input :if={@return_to} type="hidden" name="return_to" value={@return_to} />
        <label>Email <input type="email" name={@form[:email].name} value={@form[:email].value} required autofocus /></label>
        <label>Password <input type="password" name={@form[:password].name} required /></label>
        <button type="submit">Log in</button>
      </.form>
      <p class="muted">New here? <.link navigate="/register">Create an account</.link></p>
    </section>
    """
  end

  def handle_event(
        "login",
        %{"user" => %{"email" => email, "password" => password} = params},
        socket
      ) do
    case Authenticate.call(%{email: email, password: password}) do
      {:ok, _user} ->
        {:noreply,
         assign(socket,
           trigger_action: true,
           form: to_form(Map.take(params, ["email"]), as: :user)
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Wrong email or password")
         |> assign(form: to_form(%{"email" => email, "password" => ""}, as: :user))}
    end
  end
end
