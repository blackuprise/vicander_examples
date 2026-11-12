defmodule WebShop.OAuthExternalTest do
  # The shop as a resource server only: another authorization server (a fake one here, whose
  # metadata and keys are served by Req.Test) issues the tokens, the shop validates them and
  # maps the person to a shop account by their verified email.
  use WebShop.ConnCase

  alias WebShop.Infrastructure.OAuth.ExternalVerifier

  @issuer "https://idp.example"
  @resource "http://localhost:4000/mcp"
  @stub WebShop.FakeIdP

  setup do
    previous = Application.get_env(:web_shop, :oauth)

    Application.put_env(
      :web_shop,
      :oauth,
      Keyword.merge(previous,
        mode: :external,
        verifier: ExternalVerifier,
        external: [issuer: @issuer],
        req_options: [plug: {Req.Test, @stub}]
      )
    )

    ExternalVerifier.reset()

    on_exit(fn ->
      Application.put_env(:web_shop, :oauth, previous)
      ExternalVerifier.reset()
    end)

    %{key: idp_key("idp-1")}
  end

  # An issuer key, and a counter of how often its metadata and keys were asked for.
  defp idp_key(kid), do: {kid, JOSE.JWK.generate_key({:ec, :secp256r1})}

  defp public_jwk({kid, jwk}) do
    {_, map} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    Map.put(map, "kid", kid)
  end

  # The fake issuer: OpenID metadata, and a key set it can change.
  defp serve!(keys) do
    {:ok, hits} = Agent.start_link(fn -> [] end)

    Req.Test.stub(@stub, fn conn ->
      Agent.update(hits, &[conn.request_path | &1])

      case conn.request_path do
        "/.well-known/openid-configuration" ->
          Req.Test.json(conn, %{"issuer" => @issuer, "jwks_uri" => @issuer <> "/jwks"})

        "/jwks" ->
          Req.Test.json(conn, %{"keys" => Enum.map(keys, &public_jwk/1)})

        _ ->
          conn |> Plug.Conn.send_resp(404, "") |> Plug.Conn.halt()
      end
    end)

    hits
  end

  defp hits(agent), do: agent |> Agent.get(& &1) |> Enum.reverse()

  defp token({kid, jwk}, overrides \\ %{}, header \\ %{}) do
    now = System.os_time(:second)

    claims =
      Map.merge(
        %{
          "iss" => @issuer,
          "aud" => @resource,
          "sub" => "idp-user-1",
          "email" => "ann@example.com",
          "email_verified" => true,
          "iat" => now,
          "exp" => now + 600
        },
        overrides
      )

    {_, compact} =
      jwk
      |> JOSE.JWT.sign(Map.merge(%{"alg" => "ES256", "kid" => kid}, header), claims)
      |> JOSE.JWS.compact()

    compact
  end

  defp json_post(conn, path, body) do
    conn |> put_req_header("content-type", "application/json") |> post(path, Jason.encode!(body))
  end

  defp mcp(conn, token, message) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> json_post("/mcp", message)
  end

  defp rpc(method, params \\ nil) do
    message = %{"jsonrpc" => "2.0", "id" => 1, "method" => method}
    if params, do: Map.put(message, "params", params), else: message
  end

  defp tool(name, arguments \\ %{}),
    do: rpc("tools/call", %{"name" => name, "arguments" => arguments})

  describe "the shop's own authorization server is not there" do
    test "the OAuth routes answer 404", %{conn: conn} do
      for {method, path} <- [
            {:get, "/.well-known/oauth-authorization-server"},
            {:get, "/oauth/jwks"},
            {:post, "/oauth/register"},
            {:post, "/oauth/token"},
            {:get, "/oauth/authorize"}
          ] do
        assert conn |> dispatch(method, path) |> Map.fetch!(:status) == 404, path
      end
    end

    test "but the MCP endpoint says which server to log in at", %{conn: conn} do
      doc = conn |> get("/.well-known/oauth-protected-resource/mcp") |> json_response(200)

      assert doc["resource"] == @resource
      assert doc["authorization_servers"] == [@issuer]
    end

    defp dispatch(conn, :get, path), do: get(conn, path)
    defp dispatch(conn, :post, path), do: post(conn, path, %{})
  end

  describe "a token from the external server" do
    test "is accepted, and the person is the shop account with that email", %{
      conn: conn,
      key: key
    } do
      ann = register!()
      serve!([key])

      result = conn |> mcp(token(key), tool("me")) |> json_response(200)

      assert %{"result" => %{"isError" => false, "content" => [%{"text" => text}]}} = result
      assert %{"id" => id, "email" => "ann@example.com"} = Jason.decode!(text)
      assert id == ann.id
    end

    test "matches the email whatever its case", %{conn: conn, key: key} do
      register!()
      serve!([key])

      result =
        conn
        |> mcp(token(key, %{"email" => "  ANN@Example.COM "}), tool("me"))
        |> json_response(200)

      assert %{"result" => %{"isError" => false}} = result
    end

    test "has no account: refused, and none is made", %{conn: conn, key: key} do
      serve!([key])

      conn = mcp(conn, token(key, %{"email" => "stranger@example.com"}), rpc("tools/list"))

      assert conn.status == 401
      assert WebShop.Infrastructure.Repo.query!("SELECT count(*) FROM users").rows == [[0]]
    end

    test "is refused when the issuer did not verify the email, or sent none", %{
      conn: conn,
      key: key
    } do
      register!()
      serve!([key])

      for overrides <- [
            %{"email_verified" => false},
            %{"email" => nil},
            %{"email" => ""},
            %{"email" => 42}
          ] do
        conn = mcp(conn, token(key, overrides), rpc("tools/list"))
        assert conn.status == 401, inspect(overrides)
      end
    end

    test "is accepted when the issuer says nothing about verification", %{conn: conn, key: key} do
      register!()
      serve!([key])

      conn = mcp(conn, token(key, %{"email_verified" => nil}), rpc("tools/list"))
      assert conn.status == 200
    end

    test "is refused when it expired, or is for another issuer or audience", %{
      conn: conn,
      key: key
    } do
      register!()
      serve!([key])
      now = System.os_time(:second)

      for overrides <- [
            %{"exp" => now - 3600},
            %{"nbf" => now + 3600},
            %{"iss" => "https://other.example"},
            %{"aud" => "https://other.example/mcp"},
            %{"aud" => nil}
          ] do
        conn = mcp(conn, token(key, overrides), rpc("tools/list"))
        assert conn.status == 401, inspect(overrides)
      end
    end

    test "may name the endpoint among several audiences", %{conn: conn, key: key} do
      register!()
      serve!([key])

      conn =
        mcp(conn, token(key, %{"aud" => ["https://other.example", @resource]}), rpc("tools/list"))

      assert conn.status == 200
    end

    test "the audience can be configured", %{conn: conn, key: key} do
      register!()
      serve!([key])
      previous = Application.get_env(:web_shop, :oauth)

      Application.put_env(
        :web_shop,
        :oauth,
        Keyword.put(previous, :external, issuer: @issuer, audience: "shop-api")
      )

      assert conn
             |> mcp(token(key, %{"aud" => "shop-api"}), rpc("tools/list"))
             |> Map.fetch!(:status) == 200

      assert conn |> mcp(token(key), rpc("tools/list")) |> Map.fetch!(:status) == 401
    end
  end

  describe "a token that should not be trusted" do
    test "signed by a key the issuer does not publish", %{conn: conn, key: key} do
      register!()
      serve!([key])
      {_, other} = idp_key("idp-1")

      forged = token({"idp-1", other})
      assert conn |> mcp(forged, rpc("tools/list")) |> Map.fetch!(:status) == 401
    end

    test "altered after it was signed", %{conn: conn, key: key} do
      register!()
      serve!([key])
      [header, _payload, signature] = String.split(token(key), ".")

      payload =
        %{
          "iss" => @issuer,
          "aud" => @resource,
          "email" => "ann@example.com",
          "exp" => System.os_time(:second) + 9999
        }
        |> Jason.encode!()
        |> Base.url_encode64(padding: false)

      assert conn
             |> mcp("#{header}.#{payload}.#{signature}", rpc("tools/list"))
             |> Map.fetch!(:status) == 401
    end

    test "that says it is unsigned, or signed with a secret the public key is", %{
      conn: conn,
      key: key
    } do
      register!()
      serve!([key])

      payload =
        Base.url_encode64(
          Jason.encode!(%{
            "iss" => @issuer,
            "aud" => @resource,
            "email" => "ann@example.com",
            "exp" => System.os_time(:second) + 600
          }),
          padding: false
        )

      none = Base.url_encode64(~s({"alg":"none","kid":"idp-1"}), padding: false)
      assert conn |> mcp("#{none}.#{payload}.", rpc("tools/list")) |> Map.fetch!(:status) == 401

      # HS256 with the issuer's public key as the secret: the old algorithm-confusion attack.
      secret = JOSE.JWK.from_oct(Jason.encode!(public_jwk(key)))

      {_, hs} =
        secret
        |> JOSE.JWT.sign(
          %{"alg" => "HS256", "kid" => "idp-1"},
          %{
            "iss" => @issuer,
            "aud" => @resource,
            "email" => "ann@example.com",
            "exp" => System.os_time(:second) + 600
          }
        )
        |> JOSE.JWS.compact()

      assert conn |> mcp(hs, rpc("tools/list")) |> Map.fetch!(:status) == 401
    end

    test "that is not a token at all, or has no key id", %{conn: conn, key: key} do
      register!()
      serve!([key])

      for bad <- ["garbage", "a.b.c", token(key, %{}, %{"kid" => nil})] do
        assert conn |> mcp(bad, rpc("tools/list")) |> Map.fetch!(:status) == 401, bad
      end
    end

    test "a role in the token is not looked at", %{conn: conn, key: key} do
      ann = register!()
      admin = admin!()
      product = product!(admin, %{stock: 3})
      serve!([key])

      # The token says it is an admin and has every scope; the account is a customer.
      lying =
        token(key, %{"role" => "admin", "roles" => ["admin"], "scope" => "shop:read shop:write"})

      args = %{"admin_id" => ann.id, "product_id" => product.id, "quantity" => 5}

      result = conn |> mcp(lying, tool("restock_product", args)) |> json_response(200)
      assert %{"result" => %{"isError" => true, "content" => [%{"text" => text}]}} = result
      assert text =~ "Admins only"
    end
  end

  describe "scopes" do
    test "a token with none of the shop's reads, and can not write", %{conn: conn, key: key} do
      admin = admin!()
      product = product!(admin)
      serve!([key])
      args = %{"admin_id" => admin.id, "product_id" => product.id, "quantity" => 1}

      # No shop scope in the token: the default is reading.
      assert conn
             |> mcp(token(key, %{"email" => "admin@example.com"}), tool("list_products"))
             |> Map.fetch!(:status) == 200

      denied =
        mcp(
          conn,
          token(key, %{"email" => "admin@example.com", "scope" => "openid email"}),
          tool("restock_product", args)
        )

      assert denied.status == 403
    end

    test "an admin whose token carries shop:write can restock", %{conn: conn, key: key} do
      admin = admin!()
      product = product!(admin, %{stock: 3})
      serve!([key])
      args = %{"admin_id" => admin.id, "product_id" => product.id, "quantity" => 2}

      allowed = token(key, %{"email" => "admin@example.com", "scope" => "openid shop:write"})
      result = conn |> mcp(allowed, tool("restock_product", args)) |> json_response(200)

      # shop:write alone does not read, but the restock call is a write.
      assert %{"result" => %{"isError" => false}} = result
    end

    test "scopes can be a list, as some issuers send them", %{conn: conn, key: key} do
      admin = admin!()
      product = product!(admin)
      serve!([key])
      args = %{"admin_id" => admin.id, "product_id" => product.id, "quantity" => 1}

      listed = token(key, %{"email" => "admin@example.com", "scp" => ["shop:write"]})

      assert %{"result" => %{"isError" => false}} =
               conn |> mcp(listed, tool("restock_product", args)) |> json_response(200)
    end
  end

  describe "the issuer's keys" do
    test "are fetched once and kept", %{conn: conn, key: key} do
      register!()
      hits = serve!([key])

      for _ <- 1..3,
          do: assert(conn |> mcp(token(key), rpc("tools/list")) |> Map.fetch!(:status) == 200)

      assert hits(hits) == ["/.well-known/openid-configuration", "/jwks"]
    end

    test "a new key is picked up, but a bad token does not make a stream of requests", %{
      conn: conn,
      key: key
    } do
      register!()
      hits = serve!([key])
      assert conn |> mcp(token(key), rpc("tools/list")) |> Map.fetch!(:status) == 200
      before = length(hits(hits))

      # The issuer rotates. Until its key set changes a token with the new id is unknown, and
      # asking again at once finds nothing new (and is not repeated a minute long).
      rotated = idp_key("idp-2")
      assert conn |> mcp(token(rotated), rpc("tools/list")) |> Map.fetch!(:status) == 401
      assert conn |> mcp(token(rotated), rpc("tools/list")) |> Map.fetch!(:status) == 401
      assert length(hits(hits)) <= before + 2
    end

    test "a key the issuer published after the cache was made is found, when the gap has passed",
         %{conn: conn, key: key} do
      register!()
      serve!([key])
      assert conn |> mcp(token(key), rpc("tools/list")) |> Map.fetch!(:status) == 200

      new_key = idp_key("idp-2")
      serve!([key, new_key])
      # The cache says it asked a moment ago: pretend the minute is over.
      :persistent_term.put(
        {ExternalVerifier, :jwks},
        Map.update!(
          :persistent_term.get({ExternalVerifier, :jwks}),
          :attempted_at,
          &(&1 - 120_000)
        )
      )

      assert conn |> mcp(token(new_key), rpc("tools/list")) |> Map.fetch!(:status) == 200
    end

    test "known keys keep working when the issuer can not be reached", %{conn: conn, key: key} do
      register!()
      serve!([key])
      assert conn |> mcp(token(key), rpc("tools/list")) |> Map.fetch!(:status) == 200

      Req.Test.stub(@stub, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      :persistent_term.put(
        {ExternalVerifier, :jwks},
        :persistent_term.get({ExternalVerifier, :jwks})
        |> Map.update!(:fetched_at, &(&1 - :timer.hours(2)))
        |> Map.update!(:attempted_at, &(&1 - 120_000))
      )

      assert conn |> mcp(token(key), rpc("tools/list")) |> Map.fetch!(:status) == 200
    end

    test "nothing is fetched from an unreachable or untrustworthy issuer", %{conn: conn, key: key} do
      register!()
      Req.Test.stub(@stub, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
      assert conn |> mcp(token(key), rpc("tools/list")) |> Map.fetch!(:status) == 401
    end

    test "metadata naming another issuer is not believed", %{conn: conn, key: key} do
      register!()

      Req.Test.stub(@stub, fn conn ->
        Req.Test.json(conn, %{
          "issuer" => "https://evil.example",
          "jwks_uri" => @issuer <> "/jwks"
        })
      end)

      assert conn |> mcp(token(key), rpc("tools/list")) |> Map.fetch!(:status) == 401
    end

    test "are not fetched over plain http, except from the user's own machine", %{
      conn: conn,
      key: key
    } do
      register!()
      previous = Application.get_env(:web_shop, :oauth)
      hits = serve!([key])

      Application.put_env(
        :web_shop,
        :oauth,
        Keyword.put(previous, :external, issuer: @issuer, jwks_uri: "http://idp.example/jwks")
      )

      assert conn |> mcp(token(key), rpc("tools/list")) |> Map.fetch!(:status) == 401
      assert hits(hits) == []
    end
  end
end
