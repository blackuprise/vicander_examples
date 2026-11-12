defmodule WebShop.Interface.MCP.Auth do
  @moduledoc """
  The `authenticate:` function of the MCP endpoint (`DDD.MCP.HTTP`): a bearer token in, the
  caller out. The application checks the token, whoever issued it (the shop or an external
  server, see `WebShop.Domain.OAuth.TokenVerifier`), and finds the shop user; this only hands
  the answer to the transport. Whatever went wrong is just an invalid token, so a client learns
  nothing about why.
  """
  alias WebShop.Application.Queries.OAuth.AuthenticateToken

  @doc "`{:ok, %{user_id:, role:, scopes:, client_id:}}` or `{:error, :invalid_token}`."
  @spec authenticate(String.t()) :: {:ok, map()} | {:error, :invalid_token}
  def authenticate(token) do
    case AuthenticateToken.call(%{token: token}) do
      {:ok, context} -> {:ok, context}
      {:error, _} -> {:error, :invalid_token}
    end
  end
end
