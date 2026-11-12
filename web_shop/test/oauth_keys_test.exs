defmodule WebShop.OAuthKeysTest do
  # Where the signing key comes from: configuration in production, a kept file in development, a
  # fresh one in a test run. And what rotating it does.
  use WebShop.DataCase

  alias WebShop.Application.Queries.OAuth.AuthenticateToken
  alias WebShop.Domain.OAuth.{Settings, TokenSigner}
  alias WebShop.Infrastructure.OAuth.{BuiltinVerifier, JoseSigner, Keys}

  @moduletag :tmp_dir

  setup do
    previous = Application.get_env(:web_shop, :oauth)
    Keys.reset()

    on_exit(fn ->
      Application.put_env(:web_shop, :oauth, previous)
      Keys.reset()
    end)

    %{previous: previous}
  end

  defp configure(previous, extra) do
    Application.put_env(:web_shop, :oauth, Keyword.merge(previous, extra))
    Keys.reset()
  end

  defp new_jwk, do: JOSE.JWK.generate_key({:ec, :secp256r1})

  defp pem(jwk) do
    {_, pem} = JOSE.JWK.to_pem(jwk)
    pem
  end

  defp token_signed_by(jwk, sub) do
    now = System.os_time(:second)

    claims = %{
      "iss" => Settings.issuer(),
      "sub" => sub,
      "aud" => Settings.resource(),
      "scope" => "shop:read",
      "exp" => now + 600
    }

    {_, token} =
      jwk
      |> JOSE.JWT.sign(%{"alg" => "ES256", "kid" => Keys.kid(jwk)}, claims)
      |> JOSE.JWS.compact()

    token
  end

  describe "configured keys" do
    test "the first signs, all are published", %{previous: previous} do
      [current, old] = [new_jwk(), new_jwk()]
      configure(previous, private_keys: [pem(current), pem(old)])

      assert Keys.kid(Keys.signing_key()) == Keys.kid(current)
      assert %{"keys" => keys} = Keys.jwks()
      assert Enum.map(keys, & &1["kid"]) == [Keys.kid(current), Keys.kid(old)]

      assert Enum.all?(
               keys,
               &(&1["alg"] == "ES256" and &1["use"] == "sig" and not Map.has_key?(&1, "d"))
             )
    end

    test "tokens signed with the key rotated away from stay valid", %{previous: previous} do
      [current, old] = [new_jwk(), new_jwk()]
      user = register!()
      configure(previous, private_keys: [pem(current), pem(old)])

      assert {:ok, %{user_id: id}} =
               AuthenticateToken.call(%{token: token_signed_by(old, user.id)})

      assert id == user.id

      # And what the shop signs now is signed with the new one.
      {:ok, fresh} = JoseSigner.sign(%{"sub" => "x"})
      assert {:ok, %{"kid" => kid}} = fresh |> JOSE.JWS.peek_protected() |> Jason.decode()
      assert kid == Keys.kid(current)
    end

    test "a key that is no longer published is no longer trusted", %{previous: previous} do
      [current, old] = [new_jwk(), new_jwk()]
      user = register!()
      configure(previous, private_keys: [pem(current)])

      assert {:error, _} = AuthenticateToken.call(%{token: token_signed_by(old, user.id)})
    end

    test "a key that is not an EC P-256 private key is refused at once", %{previous: previous} do
      rsa = JOSE.JWK.generate_key({:rsa, 1024})
      public_only = new_jwk() |> JOSE.JWK.to_public()

      for bad <- [pem(rsa), pem(public_only), "not a key"] do
        configure(previous, private_keys: [bad])
        assert_raise ArgumentError, ~r/EC P-256 private key/, fn -> Keys.keys() end
      end
    end
  end

  describe "with no key configured" do
    test "a test run gets one of its own, kept in memory", %{previous: previous} do
      configure(previous, private_keys: [], dev_key_file: nil)

      kid = Keys.kid(Keys.signing_key())
      assert kid == Keys.kid(Keys.signing_key())

      # Another run makes another key.
      Keys.reset()
      refute Keys.kid(Keys.signing_key()) == kid
    end

    test "development keeps one in a file, private to the owner, and uses it again", %{
      previous: previous,
      tmp_dir: dir
    } do
      path = Path.join(dir, "keys/dev_jwt_key.pem")
      configure(previous, private_keys: [], dev_key_file: path)

      kid = Keys.kid(Keys.signing_key())
      assert File.exists?(path)
      assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600

      Keys.reset()
      assert Keys.kid(Keys.signing_key()) == kid
    end
  end

  describe "the signer and the verifier" do
    test "sign and verify what they should, and say no to the rest" do
      user = register!()
      now = System.os_time(:second)

      claims = %{
        "iss" => Settings.issuer(),
        "sub" => user.id,
        "aud" => Settings.resource(),
        "exp" => now + 60
      }

      assert {:ok, token} = TokenSigner.impl().sign(claims)
      assert {:ok, %{subject: {:user_id, id}, scopes: []}} = BuiltinVerifier.verify(token)
      assert id == user.id

      assert {:error, :invalid_token} = BuiltinVerifier.verify(123)
      assert {:error, :invalid_token} = BuiltinVerifier.verify(nil)

      # A claim that can not be written down is an error, not a crash.
      assert {:error, _} = JoseSigner.sign(%{"sub" => self()})
    end

    test "a null claim is an absent one", %{} do
      user = register!()
      now = System.os_time(:second)

      {:ok, token} =
        JoseSigner.sign(%{
          "iss" => Settings.issuer(),
          "sub" => user.id,
          "aud" => Settings.resource(),
          "nbf" => nil,
          "exp" => now + 60
        })

      assert {:ok, _} = BuiltinVerifier.verify(token)
    end
  end
end
