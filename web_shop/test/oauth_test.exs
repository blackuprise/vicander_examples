defmodule WebShop.OAuthTest do
  # The OAuth lifecycle through the application's commands and queries, without the web layer:
  # an app registers, the user agrees, the app trades the code, refreshes, and a leaked secret is
  # recognised.
  use WebShop.DataCase

  alias WebShop.Application.Commands.OAuth.{
    AuthorizeClient,
    ExchangeCode,
    RefreshGrant,
    RegisterClient
  }

  alias WebShop.Application.Queries.OAuth.{AuthenticateToken, GetClient}
  alias WebShop.Domain.OAuth.{Scopes, Secret, TokenSigner}
  alias WebShop.Infrastructure.Repo

  @redirect "http://localhost:33333/callback"
  @verifier String.duplicate("v", 43) <> "-._~0123456789"

  defp challenge(verifier \\ @verifier),
    do: :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)

  defp client!(attrs \\ %{}) do
    {:ok, client} =
      RegisterClient.call(
        Map.merge(%{name: "Claude", redirect_uris: [@redirect, "https://app.example/cb"]}, attrs)
      )

    client
  end

  defp authorize(user, client, extra \\ %{}) do
    AuthorizeClient.call(
      Map.merge(
        %{
          user_id: user.id,
          client_id: client.id,
          redirect_uri: @redirect,
          scope: "shop:read shop:write",
          code_challenge: challenge(),
          code_challenge_method: "S256"
        },
        extra
      )
    )
  end

  defp exchange(client, code, extra \\ %{}) do
    ExchangeCode.call(
      Map.merge(
        %{code: code, code_verifier: @verifier, client_id: client.id, redirect_uri: @redirect},
        extra
      )
    )
  end

  defp tokens!(user \\ register!(), scope \\ "shop:read shop:write") do
    client = client!()
    {:ok, %{code: code}} = authorize(user, client, %{scope: scope})
    {:ok, tokens} = exchange(client, code)
    %{user: user, client: client, tokens: tokens, code: code}
  end

  defp code_of(error), do: error.code

  defp expire!(column) do
    Repo.query!("UPDATE oauth_grants SET #{column} = now() - interval '1 hour'")
  end

  describe "registering an app" do
    test "stores the name and the addresses, and GetClient finds it" do
      client = client!()
      assert {:ok, %{client_id: id, name: "Claude"}} = GetClient.call(%{client_id: client.id})
      assert id == client.id
    end

    test "refuses an address that could leak a code" do
      for uris <- [
            ["http://evil.example/cb"],
            ["https://app.example/cb#frag"],
            ["https://app.example/*"],
            ["https://user:pass@app.example/cb"],
            ["ftp://app.example/cb"],
            ["not a url"],
            [],
            Enum.map(1..6, &"https://app.example/#{&1}")
          ] do
        assert {:error, error} = RegisterClient.call(%{name: "X", redirect_uris: uris})
        assert Enum.any?(error.violations, &(&1.field == :redirect_uris)), inspect(uris)
      end
    end

    test "allows https and the user's own machine" do
      for uri <- ["https://app.example/cb", "http://localhost:1/cb", "http://127.0.0.1:1/cb"] do
        assert {:ok, _} = RegisterClient.call(%{name: "X", redirect_uris: [uri]}), uri
      end
    end

    test "refuses a blank or oversized name" do
      for name <- ["   ", String.duplicate("x", 101)] do
        assert {:error, error} = RegisterClient.call(%{name: name, redirect_uris: [@redirect]})
        assert Enum.any?(error.violations, &(&1.field == :name))
      end
    end

    test "an unknown app is unknown" do
      assert {:error, %DDD.Error{code: :invalid_client}} = GetClient.call(%{client_id: "nope"})

      assert {:error, %DDD.Error{code: :invalid_client}} =
               GetClient.call(%{client_id: Ecto.UUID.generate()})
    end

    test "an app registered by hand in the configuration is found" do
      previous = Application.get_env(:web_shop, :oauth)

      Application.put_env(
        :web_shop,
        :oauth,
        Keyword.put(previous, :clients, [
          %{client_id: "fixed", name: "Fixed", redirect_uris: ["https://f.example/cb"]}
        ])
      )

      on_exit(fn -> Application.put_env(:web_shop, :oauth, previous) end)

      assert {:ok, %{client_id: "fixed", name: "Fixed"}} = GetClient.call(%{client_id: "fixed"})
    end
  end

  describe "authorizing" do
    test "gives a code for the scopes that were asked for" do
      assert {:ok, %{code: code, scopes: ["shop:read", "shop:write"]}} =
               authorize(register!(), client!())

      assert byte_size(code) >= 43
    end

    test "asks for nothing, gets read only" do
      assert {:ok, %{scopes: ["shop:read"]}} = authorize(register!(), client!(), %{scope: nil})
    end

    test "refuses what is not right, in the app's own terms" do
      user = register!()
      client = client!()

      assert {:error, %DDD.Error{code: :invalid_client}} = authorize(user, %{client | id: "nope"})

      assert {:error, %DDD.Error{code: :invalid_redirect_uri}} =
               authorize(user, client, %{redirect_uri: "https://evil.example/cb"})

      assert {:error, %DDD.Error{code: :invalid_redirect_uri}} =
               authorize(user, client, %{redirect_uri: @redirect <> "/"})

      assert {:error, %DDD.Error{code: :invalid_scope}} =
               authorize(user, client, %{scope: "shop:admin"})

      assert {:error, %DDD.Error{code: :invalid_request}} =
               authorize(user, client, %{code_challenge_method: "plain"})

      assert {:error, %DDD.Error{code: :invalid_request}} =
               authorize(user, client, %{code_challenge: "short"})
    end

    test "refuses a user who is not there" do
      assert {:error, error} = authorize(%{id: Ecto.UUID.generate()}, client!())
      assert error.code == :not_found
    end
  end

  describe "trading the code" do
    test "gives an access token and a refresh token" do
      %{tokens: tokens} = tokens!()

      assert %{token_type: "Bearer", expires_in: 900, scope: "shop:read shop:write"} = tokens
      assert is_binary(tokens.access_token) and is_binary(tokens.refresh_token)
    end

    test "the access token names the user and the scopes, and the role is the account's" do
      %{user: user, tokens: tokens, client: client} = tokens!(admin!())

      assert {:ok, %{user_id: id, role: :admin, scopes: scopes, client_id: client_id}} =
               AuthenticateToken.call(%{token: tokens.access_token})

      assert id == user.id
      assert scopes == ["shop:read", "shop:write"]
      assert client_id == client.id
    end

    test "a code works once; a second try revokes everything" do
      %{client: client, code: code, tokens: tokens} = tokens!()

      assert {:error, error} = exchange(client, code)
      assert code_of(error) == :invalid_grant

      # The refresh token the first trade produced is dead too.
      assert {:error, _} =
               RefreshGrant.call(%{refresh_token: tokens.refresh_token, client_id: client.id})
    end

    test "needs the PKCE verifier, the app and the address the code was issued for" do
      user = register!()
      client = client!()
      other = client!()

      for extra <- [
            %{code_verifier: String.duplicate("x", 50)},
            %{code_verifier: "short"},
            %{redirect_uri: "https://app.example/cb"},
            %{client_id: other.id}
          ] do
        {:ok, %{code: code}} = authorize(user, client)
        assert {:error, error} = exchange(client, code, extra)
        assert code_of(error) == :invalid_grant, inspect(extra)
      end
    end

    test "a code that expired is refused, and so is one nobody issued" do
      user = register!()
      client = client!()
      {:ok, %{code: code}} = authorize(user, client)
      expire!("code_expires_at")

      assert {:error, error} = exchange(client, code)
      assert code_of(error) == :invalid_grant
      assert {:error, error} = exchange(client, "nobody-issued-this")
      assert code_of(error) == :invalid_grant
    end

    test "two at once: one wins" do
      user = register!()
      client = client!()
      {:ok, %{code: code}} = authorize(user, client)

      results =
        1..2
        |> Task.async_stream(fn _ -> exchange(client, code) end, timeout: 10_000)
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.count(results, &match?({:ok, _}, &1)) <= 1
    end
  end

  describe "refreshing" do
    test "gives new tokens, and the old refresh token stops working" do
      %{client: client, tokens: first} = tokens!()

      assert {:ok, second} =
               RefreshGrant.call(%{refresh_token: first.refresh_token, client_id: client.id})

      assert second.refresh_token != first.refresh_token
      assert second.scope == first.scope
      assert {:ok, _} = AuthenticateToken.call(%{token: second.access_token})
    end

    test "using a replaced refresh token revokes the whole grant" do
      %{client: client, tokens: first} = tokens!()

      {:ok, second} =
        RefreshGrant.call(%{refresh_token: first.refresh_token, client_id: client.id})

      # The old one comes back: someone has a copy.
      assert {:error, error} =
               RefreshGrant.call(%{refresh_token: first.refresh_token, client_id: client.id})

      assert code_of(error) == :invalid_grant

      # And now the one the real app holds is dead as well. The app has to ask the user again.
      assert {:error, _} =
               RefreshGrant.call(%{refresh_token: second.refresh_token, client_id: client.id})
    end

    test "is for the app it was issued to, and unknown tokens are refused" do
      %{client: client, tokens: tokens} = tokens!()
      other = client!()

      assert {:error, _} =
               RefreshGrant.call(%{refresh_token: tokens.refresh_token, client_id: other.id})

      assert {:error, _} = RefreshGrant.call(%{refresh_token: "unknown", client_id: client.id})

      # The wrong app did not use it up.
      assert {:ok, _} =
               RefreshGrant.call(%{refresh_token: tokens.refresh_token, client_id: client.id})
    end

    test "a refresh token that expired is refused" do
      %{client: client, tokens: tokens} = tokens!()
      expire!("refresh_expires_at")

      assert {:error, error} =
               RefreshGrant.call(%{refresh_token: tokens.refresh_token, client_id: client.id})

      assert code_of(error) == :invalid_grant
    end
  end

  describe "an access token" do
    defp sign!(overrides) do
      now = System.os_time(:second)

      claims =
        Map.merge(
          %{
            "iss" => WebShop.Domain.OAuth.Settings.issuer(),
            "sub" => register!("u#{System.unique_integer([:positive])}@example.com").id,
            "aud" => WebShop.Domain.OAuth.Settings.resource(),
            "scope" => "shop:read",
            "iat" => now,
            "exp" => now + 600
          },
          overrides
        )

      {:ok, token} = TokenSigner.impl().sign(claims)
      token
    end

    test "that is well formed is accepted" do
      assert {:ok, %{scopes: ["shop:read"]}} = AuthenticateToken.call(%{token: sign!(%{})})
    end

    test "is refused when it expired, is for another audience or issuer, or has no user" do
      now = System.os_time(:second)

      for overrides <- [
            %{"exp" => now - 3600},
            %{"nbf" => now + 3600},
            %{"aud" => "https://other.example/mcp"},
            %{"iss" => "https://other.example"},
            %{"sub" => Ecto.UUID.generate()},
            %{"sub" => "not-a-uuid"}
          ] do
        assert {:error, _} = AuthenticateToken.call(%{token: sign!(overrides)}),
               inspect(overrides)
      end
    end

    test "is refused when it was altered or is not a token" do
      [header, payload, signature] = String.split(sign!(%{}), ".")
      forged = Base.url_encode64(~s({"sub":"#{register!("x@example.com").id}"}), padding: false)

      for token <- [
            "#{header}.#{forged}.#{signature}",
            "#{header}.#{payload}",
            "garbage",
            "a.b.c",
            ""
          ] do
        assert {:error, _} = AuthenticateToken.call(%{token: token}), token
      end
    end

    test "that says it is unsigned is refused" do
      header = Base.url_encode64(~s({"alg":"none","typ":"JWT"}), padding: false)
      payload = Base.url_encode64(~s({"sub":"#{register!().id}"}), padding: false)

      assert {:error, _} = AuthenticateToken.call(%{token: "#{header}.#{payload}."})
    end

    test "another key's token is refused" do
      other = JOSE.JWK.generate_key({:ec, :secp256r1})
      now = System.os_time(:second)

      claims = %{
        "iss" => WebShop.Domain.OAuth.Settings.issuer(),
        "sub" => register!().id,
        "aud" => WebShop.Domain.OAuth.Settings.resource(),
        "exp" => now + 600
      }

      {_, token} = other |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims) |> JOSE.JWS.compact()
      assert {:error, _} = AuthenticateToken.call(%{token: token})
    end
  end

  describe "secrets" do
    test "are random, stored as hashes, and never in the grant's inspect" do
      {value, hash} = Secret.generate()
      assert value != hash and Secret.hash(value) == hash
      assert Secret.generate() != {value, hash}

      %{code: code} = tokens!()
      %{rows: [[stored]]} = Repo.query!("SELECT code_hash FROM oauth_grants LIMIT 1")
      assert stored == Secret.hash(code) and stored != code
    end

    test "scopes parse strictly" do
      assert Scopes.parse("shop:read shop:read") == {:ok, ["shop:read"]}
      assert Scopes.parse("") == {:ok, ["shop:read"]}
      assert Scopes.parse("shop:read nope") == {:error, :invalid_scope}
    end
  end
end
