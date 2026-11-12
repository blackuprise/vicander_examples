defmodule WebShop.Domain.OAuth.TokenVerifier do
  @moduledoc """
  Port: how the shop checks an access token it is shown, whoever issued it. The adapter for the
  shop's own authorization server and the one for an external server both answer with the same
  thing: who the token is for, what it allows, and which app holds it. Nothing else of the token
  reaches the application, and a role in a token is never looked at.

  `subject` says how to find the user: `{:user_id, id}` for a token the shop issued, or
  `{:email, email}` (verified by the issuer) for an external server's.
  """

  @type claims :: %{
          subject: {:user_id, String.t()} | {:email, String.t()},
          scopes: [String.t()],
          client_id: String.t() | nil
        }

  @doc "Check the signature, issuer, audience and expiry, and say who the token is for."
  @callback verify(token :: String.t()) :: {:ok, claims()} | {:error, :invalid_token}

  @doc "The adapter configured for this port."
  def impl, do: :web_shop |> Application.fetch_env!(:oauth) |> Keyword.fetch!(:verifier)
end
