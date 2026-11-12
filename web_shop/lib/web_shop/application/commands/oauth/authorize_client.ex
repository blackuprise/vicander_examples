defmodule WebShop.Application.Commands.OAuth.AuthorizeClient do
  @moduledoc """
  The user agreed on the consent page: open a grant and hand back an authorization code for the
  app. Everything the app asked for is checked again here and not trusted from the page: the app
  exists, the redirect address is one it registered (an exact match), the scopes exist, and the
  PKCE challenge is a SHA-256 one (method `S256`; the plain method is refused).

  The user is `loads: true`, so a user who does not exist fails before anything runs.
  """
  use DDD.Command

  alias WebShop.Application.OAuth.Access
  alias WebShop.Application.Queries.OAuth.GetClient
  alias WebShop.Domain.OAuth.Grant
  alias WebShop.Domain.OAuth.Grant.Repository, as: GrantRepository
  alias WebShop.Domain.OAuth.Scopes
  alias WebShop.Domain.User

  command do
    description "Give an app an authorization code for a user who agreed"

    field :user_id, {:ref, User}, required: true, loads: true, description: "Who agreed"
    field :client_id, :string, required: true, description: "The app"
    field :redirect_uri, :string, required: true, description: "Where the code is sent"
    field :scope, :string, description: "The scopes asked for, separated by spaces"
    field :code_challenge, :string, required: true, description: "The PKCE challenge"
    field :code_challenge_method, :string, required: true, description: "Must be S256"
  end

  @impl DDD.Command
  def execute(%__MODULE__{} = command) do
    with :ok <- check_method(command.code_challenge_method),
         :ok <- check_challenge(command.code_challenge),
         {:ok, client} <- GetClient.call(%{client_id: command.client_id}),
         :ok <- check_redirect(client, command.redirect_uri),
         {:ok, scopes} <- scopes(command.scope),
         {:ok, grant, code} <-
           Grant.open(
             [
               client_id: command.client_id,
               user_id: command.user_id,
               scopes: scopes,
               redirect_uri: command.redirect_uri,
               code_challenge: command.code_challenge
             ],
             DateTime.truncate(DateTime.utc_now(), :second)
           ),
         {:ok, _grant} <- GrantRepository.impl().save(grant) do
      {:ok, %{code: code, scopes: scopes}}
    end
  end

  defp check_method("S256"), do: :ok
  defp check_method(_), do: invalid_request("code_challenge_method must be S256")

  defp check_challenge(challenge) do
    if Access.challenge?(challenge),
      do: :ok,
      else: invalid_request("code_challenge is not a SHA-256 challenge")
  end

  defp check_redirect(client, uri) do
    if uri in client.redirect_uris,
      do: :ok,
      else: {:error, {:invalid_redirect_uri, "that address is not registered for this app"}}
  end

  defp scopes(scope) do
    case Scopes.parse(scope) do
      {:ok, scopes} -> {:ok, scopes}
      {:error, :invalid_scope} -> {:error, {:invalid_scope, "unknown scope"}}
    end
  end

  defp invalid_request(message), do: {:error, {:invalid_request, message}}
end
