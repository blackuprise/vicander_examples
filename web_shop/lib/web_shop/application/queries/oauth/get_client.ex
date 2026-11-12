defmodule WebShop.Application.Queries.OAuth.GetClient do
  @moduledoc """
  An app by its client id: one registered by hand in the configuration, or one that registered
  itself. What the consent page needs to show, and what the authorize and token steps check
  redirect addresses against.
  """
  use DDD.Query, transaction: false

  alias WebShop.Domain.OAuth.Client
  alias WebShop.Domain.OAuth.Client.Repository, as: ClientRepository
  alias WebShop.Domain.OAuth.Settings

  query do
    description "An OAuth client (an app) by id: its name and the addresses it may be sent back to"

    field :client_id, :string, required: true, description: "The client id"
  end

  @impl DDD.Query
  def execute(%__MODULE__{client_id: client_id}) do
    case configured(client_id) || registered(client_id) do
      nil -> {:error, {:invalid_client, "unknown app"}}
      client -> {:ok, client}
    end
  end

  defp configured(client_id) do
    Enum.find_value(Settings.clients(), fn client ->
      if to_string(client.client_id) == client_id do
        %{client_id: client_id, name: client.name, redirect_uris: client.redirect_uris}
      end
    end)
  end

  # A client id that is not a UUID can not be a registered one.
  defp registered(client_id) do
    with {:ok, _} <- Ecto.UUID.cast(client_id),
         {:ok, %Client{} = client} <- ClientRepository.impl().find_by_id(client_id) do
      %{client_id: client.id, name: client.name, redirect_uris: client.redirect_uris}
    else
      _ -> nil
    end
  end
end
