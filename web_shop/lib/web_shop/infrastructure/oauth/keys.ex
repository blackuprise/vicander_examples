defmodule WebShop.Infrastructure.OAuth.Keys do
  @moduledoc """
  The key the shop signs its access tokens with (ES256), and the public half the world verifies
  them with (`/oauth/jwks`).

  **Where the key comes from.** `config :web_shop, :oauth, private_keys: [pem, ...]`, which
  `runtime.exs` fills from `SHOP_JWT_PRIVATE_KEY` (and in production the app does not start
  without it). The first key signs; all of them are published, so tokens signed with the key you
  rotated away from stay valid until they expire (15 minutes). With no key configured, which is
  development and test, one is generated: development keeps it in `priv/dev_jwt_key.pem`
  (git-ignored) so tokens survive a restart, and a test run makes a fresh one.

  A key id (`kid`) is the key's RFC 7638 thumbprint.
  """

  @cache {__MODULE__, :keys}

  @doc "The key that signs, as a `JOSE.JWK`."
  @spec signing_key() :: JOSE.JWK.t()
  def signing_key, do: hd(keys())

  @doc "Every key a token may have been signed with, newest first."
  @spec keys() :: [JOSE.JWK.t()]
  def keys do
    case :persistent_term.get(@cache, nil) do
      nil ->
        keys = load()
        :persistent_term.put(@cache, keys)
        keys

      keys ->
        keys
    end
  end

  @doc "The key id of a key."
  @spec kid(JOSE.JWK.t()) :: String.t()
  def kid(jwk), do: JOSE.JWK.thumbprint(jwk)

  @doc "The public keys as a JWK Set (RFC 7517), ready to be encoded as JSON."
  @spec jwks() :: %{String.t() => [map()]}
  def jwks do
    %{"keys" => Enum.map(keys(), &public_map/1)}
  end

  @doc "Forget the loaded keys (for tests that change the configuration)."
  @spec reset() :: :ok
  def reset do
    :persistent_term.erase(@cache)
    :ok
  end

  defp public_map(jwk) do
    {_, map} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    Map.merge(map, %{"kid" => kid(jwk), "use" => "sig", "alg" => "ES256"})
  end

  defp load do
    case configured() do
      [] -> [generated()]
      pems -> Enum.map(pems, &from_pem!/1)
    end
  end

  defp configured do
    :web_shop |> Application.get_env(:oauth, []) |> Keyword.get(:private_keys, []) |> List.wrap()
  end

  defp from_pem!(pem) do
    jwk = JOSE.JWK.from_pem(pem)

    case JOSE.JWK.to_map(jwk) do
      {_, %{"kty" => "EC", "crv" => "P-256", "d" => _}} -> jwk
      _ -> raise ArgumentError, "SHOP_JWT_PRIVATE_KEY must be an EC P-256 private key (ES256)"
    end
  end

  # Development keeps the key it made; a test run (`dev_key_file: nil`) keeps it in memory only.
  defp generated do
    case dev_key_file() do
      nil -> new_key()
      path -> read_or_create(path)
    end
  end

  defp dev_key_file do
    :web_shop |> Application.get_env(:oauth, []) |> Keyword.get(:dev_key_file)
  end

  defp read_or_create(path) do
    if File.exists?(path) do
      from_pem!(File.read!(path))
    else
      jwk = new_key()
      File.mkdir_p!(Path.dirname(path))
      {_, pem} = JOSE.JWK.to_pem(jwk)
      File.write!(path, pem)
      File.chmod!(path, 0o600)
      jwk
    end
  end

  defp new_key, do: JOSE.JWK.generate_key({:ec, :secp256r1})
end
