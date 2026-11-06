defmodule WebShop.Interface.Web.RegisterLive do
  @moduledoc """
  Create a customer account, then log in through the session controller. Only name, email and
  password are passed on: a role in the form data is never read.
  """
  use Phoenix.LiveView, layout: {WebShop.Interface.Web.Layouts, :app}

  alias WebShop.Application.Commands.User.RegisterUser
  alias WebShop.Interface.Web.Format

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Register", trigger_action: false, errors: %{})
     |> assign(form: to_form(%{"name" => "", "email" => "", "password" => ""}, as: :user))}
  end

  def render(assigns) do
    ~H"""
    <section class="card narrow">
      <h1>Create an account</h1>
      <.form for={@form} id="register-form" action="/session" phx-submit="register" phx-trigger-action={@trigger_action}>
        <label>Name <input type="text" name={@form[:name].name} value={@form[:name].value} required autofocus /></label>
        <p :for={m <- @errors[:name] || []} class="field-error">{m}</p>
        <label>Email <input type="email" name={@form[:email].name} value={@form[:email].value} required /></label>
        <p :for={m <- @errors[:email] || []} class="field-error">{m}</p>
        <label>Password (8 characters or more) <input type="password" name={@form[:password].name} value={@form[:password].value} required /></label>
        <p :for={m <- @errors[:password] || []} class="field-error">{m}</p>
        <button type="submit">Register</button>
      </.form>
      <p class="muted">Already registered? <.link navigate="/login">Log in</.link></p>
    </section>
    """
  end

  def handle_event("register", %{"user" => params}, socket) do
    attrs = %{name: params["name"], email: params["email"], password: params["password"]}

    case RegisterUser.call(attrs) do
      {:ok, _user} ->
        {:noreply, assign(socket, trigger_action: true, form: to_form(params, as: :user))}

      {:error, error} ->
        {:noreply,
         assign(socket,
           errors: Format.field_errors(error),
           form: to_form(Map.put(params, "password", ""), as: :user)
         )}
    end
  end
end
