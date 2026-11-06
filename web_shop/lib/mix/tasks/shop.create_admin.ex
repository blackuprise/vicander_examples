defmodule Mix.Tasks.Shop.CreateAdmin do
  @shortdoc "Creates an admin user: mix shop.create_admin NAME EMAIL PASSWORD"
  @moduledoc """
  Creates an admin. There is no way to become an admin from the web.

      mix shop.create_admin "Ann" ann@example.com a-long-password
  """
  use Boundary, classify_to: WebShop
  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run([name, email, password]) do
    case WebShop.Application.Commands.User.RegisterUser.call(%{
           name: name,
           email: email,
           password: password,
           role: :admin
         }) do
      {:ok, user} ->
        Mix.shell().info("Created admin #{user.email}")

      {:error, error} ->
        Mix.raise("Could not create the admin: #{inspect(DDD.Error.to_map(error))}")
    end
  end

  def run(_), do: Mix.raise("usage: mix shop.create_admin NAME EMAIL PASSWORD")
end
