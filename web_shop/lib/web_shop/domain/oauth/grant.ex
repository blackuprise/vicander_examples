defmodule WebShop.Domain.OAuth.Grant do
  @moduledoc """
  Aggregate: one user's consent to one app, and the codes it was given because of it.

  The life of a grant:

    1. **Open.** The user said yes on the consent page. The grant holds a single-use
       *authorization code* (60 seconds), bound to the app, the redirect address and the PKCE
       challenge the app sent.
    2. **Redeem.** The app trades the code, with the PKCE verifier, for a refresh token. The code
       is spent and stays on record, so presenting it again is recognised as a replay.
    3. **Rotate.** Each use of the refresh token replaces it. The one before is kept: if it is
       presented again it has leaked (the real app already moved on), and the whole grant is
       revoked.
    4. **Revoke.** The grant stops working at once for refreshing; access tokens already issued
       run out within their 15 minutes.

  Codes and refresh tokens are stored as hashes (`WebShop.Domain.OAuth.Secret`). The grant never
  holds the secrets themselves, and its `inspect` leaves the hashes out.
  """
  use DDD.Aggregate

  alias WebShop.Domain.OAuth.Secret

  @derive {Inspect, except: [:code_hash, :code_challenge, :refresh_hash, :previous_refresh_hash]}

  @code_ttl_seconds 60
  @refresh_ttl_seconds 30 * 24 * 3600

  aggregate do
    description "A user's consent to an app, and the codes it was given because of it"

    identity :id, :uuid
    field :client_id, :string, required: true, description: "The app"
    field :user_id, :uuid, required: true, description: "The user who agreed"
    field :scopes, {:array, :string}, required: true, description: "What the user agreed to"
    field :redirect_uri, :string, required: true, description: "Where the code was sent"
    field :code_challenge, :string, required: true, description: "The PKCE challenge (S256)"
    field :code_hash, :string, description: "Hash of the authorization code"
    field :code_expires_at, :datetime, description: "When the code stops working"
    field :code_used_at, :datetime, description: "When the code was traded in"
    field :refresh_hash, :string, description: "Hash of the current refresh token"
    field :previous_refresh_hash, :string, description: "Hash of the one it replaced"
    field :refresh_expires_at, :datetime, description: "When the refresh token stops working"
    field :last_used_at, :datetime, description: "When a token was last issued"
    field :revoked_at, :datetime, description: "When the grant was revoked"
  end

  @doc """
  A grant with a fresh authorization code. Returns `{:ok, grant, code}`; the code is for the
  app, and only its hash is in the grant.
  """
  @spec open(keyword(), DateTime.t()) :: {:ok, struct(), String.t()} | {:error, DDD.Error.t()}
  def open(attrs, %DateTime{} = now) do
    {code, code_hash} = Secret.generate()

    attrs =
      Keyword.merge(attrs,
        code_hash: code_hash,
        code_expires_at: DateTime.add(now, @code_ttl_seconds, :second)
      )

    with {:ok, grant} <- new(attrs), do: {:ok, grant, code}
  end

  @doc """
  Trade the authorization code for a refresh token (whose hash is `refresh_hash`). Refused when
  the grant is revoked, the code was already used or has expired, or the app, the redirect
  address or the PKCE verifier is not the one the code was issued for.
  """
  defop redeem_code(grant, client_id, redirect_uri, verifier, refresh_hash, now) do
    cond do
      revoked?(grant) ->
        invalid("the grant was revoked")

      not is_nil(grant.code_used_at) ->
        invalid("the code was already used")

      is_nil(grant.code_hash) or expired?(grant.code_expires_at, now) ->
        invalid("the code expired")

      grant.client_id != client_id ->
        invalid("the code was issued to another app")

      grant.redirect_uri != redirect_uri ->
        invalid("the redirect address differs")

      not pkce_valid?(grant.code_challenge, verifier) ->
        invalid("the PKCE verifier does not match")

      true ->
        issue_refresh(%{grant | code_used_at: now}, refresh_hash, now)
    end
  end

  @doc "Replace the refresh token (whose hash is `new_hash`), keeping the one before it."
  defop rotate_refresh(grant, new_hash, now) do
    cond do
      revoked?(grant) -> invalid("the grant was revoked")
      is_nil(grant.refresh_hash) -> invalid("no refresh token was issued")
      expired?(grant.refresh_expires_at, now) -> invalid("the refresh token expired")
      true -> issue_refresh(%{grant | previous_refresh_hash: grant.refresh_hash}, new_hash, now)
    end
  end

  @doc "Stop the grant from being refreshed or redeemed. Revoking a revoked grant changes nothing."
  defop revoke(grant, now) do
    if revoked?(grant), do: grant, else: %{grant | revoked_at: now}
  end

  @doc """
  Which of the grant's refresh tokens a hash is: `:current`, `:previous` (a replaced one, so a
  token that leaked) or `:none`.
  """
  @spec refresh_match(struct(), String.t() | nil) :: :current | :previous | :none
  def refresh_match(%__MODULE__{refresh_hash: hash}, hash) when is_binary(hash), do: :current

  def refresh_match(%__MODULE__{previous_refresh_hash: hash}, hash) when is_binary(hash),
    do: :previous

  def refresh_match(_grant, _hash), do: :none

  @doc "True once the code has been traded in."
  @spec code_used?(struct()) :: boolean()
  def code_used?(%__MODULE__{code_used_at: used}), do: not is_nil(used)

  @doc "True when the grant was revoked."
  @spec revoked?(struct()) :: boolean()
  def revoked?(%__MODULE__{revoked_at: revoked}), do: not is_nil(revoked)

  @doc """
  Whether `verifier` is the secret behind a PKCE `challenge` (method S256): the challenge is the
  URL-safe, unpadded Base64 of the verifier's SHA-256. A verifier is 43 to 128 characters from a
  small alphabet (RFC 7636), and the comparison does not leak where they differ.
  """
  @spec pkce_valid?(String.t() | nil, String.t() | nil) :: boolean()
  def pkce_valid?(challenge, verifier) when is_binary(challenge) and is_binary(verifier) do
    computed = :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)

    String.match?(verifier, ~r/\A[A-Za-z0-9\-._~]{43,128}\z/) and
      byte_size(computed) == byte_size(challenge) and :crypto.hash_equals(computed, challenge)
  end

  def pkce_valid?(_challenge, _verifier), do: false

  defp issue_refresh(grant, refresh_hash, now) do
    %{
      grant
      | refresh_hash: refresh_hash,
        refresh_expires_at: DateTime.add(now, @refresh_ttl_seconds, :second),
        last_used_at: now
    }
  end

  defp expired?(nil, _now), do: true
  defp expired?(at, now), do: DateTime.compare(now, at) != :lt

  defp invalid(message) do
    {:error, DDD.Error.business(entity: __MODULE__, code: :invalid_grant, message: message)}
  end
end
