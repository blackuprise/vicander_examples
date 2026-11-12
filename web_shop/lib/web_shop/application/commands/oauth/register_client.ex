defmodule WebShop.Application.Commands.OAuth.RegisterClient do
  @moduledoc """
  An app registers itself (RFC 7591, dynamic client registration) with a name and the addresses
  it may be sent back to. It stays a public client: no secret is issued. Nobody is logged in
  when this runs, which is why the redirect rules are strict (see `Client.Specs`).
  """
  use DDD.Command

  alias WebShop.Domain.OAuth.Client
  alias WebShop.Domain.OAuth.Client.Repository, as: ClientRepository

  command do
    description "Register an app that will ask users for access (a public client)"

    field :name, :string, required: true, description: "The app's name"

    field :redirect_uris, {:array, :string},
      required: true,
      description: "Where the app may be sent back"
  end

  @impl DDD.Command
  def execute(%__MODULE__{name: name, redirect_uris: redirect_uris}) do
    with {:ok, client} <- Client.new(name: String.trim(name), redirect_uris: redirect_uris) do
      ClientRepository.impl().save(client)
    end
  end
end
