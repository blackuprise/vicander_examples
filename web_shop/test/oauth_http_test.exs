defmodule WebShop.OAuthHTTPTest do
  # The shop as its own authorization server, over HTTP, the way an AI client uses it: it
  # registers, sends the user to log in and agree, trades the code for tokens, and calls /mcp.
  use WebShop.ConnCase

  alias WebShop.Application.Commands.OAuth.{AuthorizeClient, ExchangeCode, RegisterClient}

  @redirect "http://localhost:33333/callback"
  @verifier String.duplicate("v", 43) <> "-._~0123456789"
  @issuer "http://localhost:4000"

  defp challenge, do: :sha256 |> :crypto.hash(@verifier) |> Base.url_encode64(padding: false)

  defp json_post(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end

  defp register_app(conn, extra \\ %{}) do
    conn
    |> json_post(
      "/oauth/register",
      Map.merge(%{client_name: "Claude", redirect_uris: [@redirect]}, extra)
    )
    |> json_response(201)
  end

  defp authorize_params(client_id, extra \\ %{}) do
    Map.merge(
      %{
        "client_id" => client_id,
        "redirect_uri" => @redirect,
        "response_type" => "code",
        "scope" => "shop:read shop:write",
        "state" => "state-123",
        "code_challenge" => challenge(),
        "code_challenge_method" => "S256"
      },
      extra
    )
  end

  # The query of the address a response sent the browser to.
  defp redirect_query(conn) do
    uri = conn |> redirected_to(302) |> URI.parse()
    {uri, URI.decode_query(uri.query || "")}
  end

  defp token_request(conn, params), do: post(conn, "/oauth/token", params)

  # Tokens for `user`, through the commands (the flow over HTTP is tested once, below).
  defp tokens_for(user, scope \\ "shop:read shop:write") do
    {:ok, client} = RegisterClient.call(%{name: "Claude", redirect_uris: [@redirect]})

    {:ok, %{code: code}} =
      AuthorizeClient.call(%{
        user_id: user.id,
        client_id: client.id,
        redirect_uri: @redirect,
        scope: scope,
        code_challenge: challenge(),
        code_challenge_method: "S256"
      })

    {:ok, tokens} =
      ExchangeCode.call(%{
        code: code,
        code_verifier: @verifier,
        client_id: client.id,
        redirect_uri: @redirect
      })

    tokens
  end

  defp mcp(conn, token, message) do
    conn =
      if token, do: put_req_header(conn, "authorization", "Bearer #{token}"), else: conn

    json_post(conn, "/mcp", message)
  end

  defp rpc(method, params \\ nil, id \\ 1) do
    message = %{"jsonrpc" => "2.0", "id" => id, "method" => method}
    if params, do: Map.put(message, "params", params), else: message
  end

  defp call_tool(name, arguments \\ %{}),
    do: rpc("tools/call", %{"name" => name, "arguments" => arguments})

  describe "the documents a client reads first" do
    test "the MCP endpoint says who to log in at", %{conn: conn} do
      doc = conn |> get("/.well-known/oauth-protected-resource/mcp") |> json_response(200)

      assert doc["resource"] == @issuer <> "/mcp"
      assert doc["authorization_servers"] == [@issuer]
      assert "shop:read" in doc["scopes_supported"]
      assert doc["bearer_methods_supported"] == ["header"]
    end

    test "the authorization server says where everything is, and what it supports", %{conn: conn} do
      doc = conn |> get("/.well-known/oauth-authorization-server") |> json_response(200)

      assert doc["issuer"] == @issuer
      assert doc["authorization_endpoint"] == @issuer <> "/oauth/authorize"
      assert doc["token_endpoint"] == @issuer <> "/oauth/token"
      assert doc["registration_endpoint"] == @issuer <> "/oauth/register"
      assert doc["jwks_uri"] == @issuer <> "/oauth/jwks"
      assert doc["code_challenge_methods_supported"] == ["S256"]
      assert doc["token_endpoint_auth_methods_supported"] == ["none"]
      assert doc["authorization_response_iss_parameter_supported"] == true
    end

    test "the keys are public EC keys with an id", %{conn: conn} do
      %{"keys" => [key | _]} = conn |> get("/oauth/jwks") |> json_response(200)

      assert %{"kty" => "EC", "crv" => "P-256", "alg" => "ES256", "use" => "sig"} = key
      assert is_binary(key["kid"])
      refute Map.has_key?(key, "d")
    end
  end

  describe "registering an app" do
    test "gives a client id, and says it is a public client", %{conn: conn} do
      client = register_app(conn)

      assert client["client_name"] == "Claude"
      assert client["redirect_uris"] == [@redirect]
      assert client["token_endpoint_auth_method"] == "none"
      assert client["grant_types"] == ["authorization_code", "refresh_token"]
      assert {:ok, _} = Ecto.UUID.cast(client["client_id"])
    end

    test "refuses an address that could leak a code, in RFC 7591's terms", %{conn: conn} do
      for uris <- [["http://evil.example/cb"], ["https://a.example/cb#x"], [], "not-a-list"] do
        body =
          conn
          |> json_post("/oauth/register", %{client_name: "X", redirect_uris: uris})
          |> json_response(400)

        assert body["error"] == "invalid_redirect_uri", inspect(uris)
        assert is_binary(body["error_description"])
      end
    end

    test "refuses a missing name", %{conn: conn} do
      body =
        conn
        |> json_post("/oauth/register", %{redirect_uris: [@redirect]})
        |> json_response(400)

      assert body["error"] == "invalid_client_metadata"
    end
  end

  describe "the user's part" do
    setup %{conn: conn} do
      client = register_app(conn)
      %{client_id: client["client_id"]}
    end

    test "someone who is not logged in is sent to log in, and brought back here", %{
      conn: conn,
      client_id: client_id
    } do
      conn = get(conn, "/oauth/authorize", authorize_params(client_id))

      {uri, query} = redirect_query(conn)
      assert uri.path == "/login"
      assert query["return_to"] =~ "/oauth/authorize?"
      assert query["return_to"] =~ "client_id=#{client_id}"
    end

    test "logging in with that return_to goes back to the consent page", %{
      conn: conn,
      client_id: client_id
    } do
      register!()
      back = "/oauth/authorize?" <> URI.encode_query(authorize_params(client_id))

      conn =
        post(conn, "/session", %{
          "user" => %{"email" => "ann@example.com", "password" => "long-enough-password"},
          "return_to" => back
        })

      assert redirected_to(conn) == back
    end

    test "a return_to that is not an authorization request is ignored", %{conn: conn} do
      register!()

      for evil <- [
            "https://evil.example",
            "//evil.example/x",
            "/admin/report",
            "/oauth/token",
            "javascript:alert(1)"
          ] do
        conn =
          post(conn, "/session", %{
            "user" => %{"email" => "ann@example.com", "password" => "long-enough-password"},
            "return_to" => evil
          })

        assert redirected_to(conn) == "/", evil
      end
    end

    test "shows who is asking and what for, and the address the user goes back to", %{
      conn: conn,
      client_id: client_id
    } do
      user = register!()
      conn = conn |> log_in(user) |> get("/oauth/authorize", authorize_params(client_id))

      html = html_response(conn, 200)
      assert html =~ "Allow access?"
      assert html =~ "Name given by the app"
      assert html =~ "Claude"
      assert html =~ "localhost:33333"
      assert html =~ "ann@example.com"
      assert html =~ "shop:read" and html =~ "shop:write"
      assert html =~ ~s(name="decision" value="allow")
      assert html =~ ~s(name="decision" value="deny")

      # It can not be put in a frame, and is not kept.
      assert get_resp_header(conn, "x-frame-options") == ["DENY"]
      assert get_resp_header(conn, "content-security-policy") == ["frame-ancestors 'none'"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "Allow sends the code back to the app, with state and issuer", %{
      conn: conn,
      client_id: client_id
    } do
      user = register!()

      conn =
        conn
        |> log_in(user)
        |> post("/oauth/authorize", Map.put(authorize_params(client_id), "decision", "allow"))

      {uri, query} = redirect_query(conn)
      assert "#{uri.scheme}://#{uri.host}:#{uri.port}#{uri.path}" == @redirect
      assert query["state"] == "state-123"
      assert query["iss"] == @issuer
      assert byte_size(query["code"]) >= 43
      refute Map.has_key?(query, "error")
      assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
    end

    test "Deny says so, and gives no code", %{conn: conn, client_id: client_id} do
      conn =
        conn
        |> log_in(register!())
        |> post("/oauth/authorize", Map.put(authorize_params(client_id), "decision", "deny"))

      {_uri, query} = redirect_query(conn)
      assert query["error"] == "access_denied"
      assert query["state"] == "state-123"
      assert query["iss"] == @issuer
      refute Map.has_key?(query, "code")
    end

    test "an address the app did not register gets an error page, never a redirect", %{
      conn: conn,
      client_id: client_id
    } do
      conn =
        conn
        |> log_in(register!())
        |> get(
          "/oauth/authorize",
          authorize_params(client_id, %{"redirect_uri" => "https://evil.example/cb"})
        )

      assert html_response(conn, 400) =~ "can not be completed"
      assert get_resp_header(conn, "location") == []
    end

    test "nor does an app nobody knows, or a request with no app", %{conn: conn} do
      conn = log_in(conn, register!())

      for params <- [%{"client_id" => Ecto.UUID.generate(), "redirect_uri" => @redirect}, %{}] do
        conn = get(conn, "/oauth/authorize", params)
        assert html_response(conn, 400) =~ "can not be completed"
        assert get_resp_header(conn, "location") == []
      end
    end

    test "the decision is checked again: a changed address gets an error page", %{
      conn: conn,
      client_id: client_id
    } do
      conn =
        conn
        |> log_in(register!())
        |> post(
          "/oauth/authorize",
          client_id
          |> authorize_params(%{"redirect_uri" => "https://evil.example/cb"})
          |> Map.put("decision", "allow")
        )

      assert html_response(conn, 400) =~ "can not be completed"
      assert get_resp_header(conn, "location") == []
    end

    test "deciding without being logged in gets an error page", %{
      conn: conn,
      client_id: client_id
    } do
      conn =
        post(conn, "/oauth/authorize", Map.put(authorize_params(client_id), "decision", "allow"))

      assert html_response(conn, 400) =~ "logged out"
    end

    test "what is wrong with the request itself goes back to the app, at its own address", %{
      conn: conn,
      client_id: client_id
    } do
      conn = log_in(conn, register!())

      for {extra, error} <- [
            {%{"response_type" => "token"}, "unsupported_response_type"},
            {%{"code_challenge_method" => "plain"}, "invalid_request"},
            {%{"code_challenge" => nil}, "invalid_request"},
            {%{"scope" => "shop:admin"}, "invalid_scope"}
          ] do
        response = get(conn, "/oauth/authorize", authorize_params(client_id, extra))
        {uri, query} = redirect_query(response)

        assert uri.host == "localhost" and uri.port == 33333
        assert query["error"] == error, inspect(extra)
        assert query["state"] == "state-123"
        assert query["iss"] == @issuer
      end
    end

    test "an app with one address may leave it out", %{conn: conn, client_id: client_id} do
      conn =
        conn
        |> log_in(register!())
        |> get("/oauth/authorize", Map.delete(authorize_params(client_id), "redirect_uri"))

      assert html_response(conn, 200) =~ "Allow access?"
    end
  end

  describe "the whole way, over HTTP" do
    test "register, agree, trade the code, call /mcp, refresh", %{conn: conn} do
      user = register!()
      client = register_app(conn)

      # The user agrees on the consent page.
      allowed =
        conn
        |> log_in(user)
        |> post(
          "/oauth/authorize",
          Map.put(authorize_params(client["client_id"]), "decision", "allow")
        )

      {_uri, %{"code" => code}} = redirect_query(allowed)

      # The app trades the code. Not the logged-in conn: the app has no cookie.
      tokens =
        build_conn()
        |> token_request(%{
          "grant_type" => "authorization_code",
          "code" => code,
          "code_verifier" => @verifier,
          "client_id" => client["client_id"],
          "redirect_uri" => @redirect
        })
        |> json_response(200)

      assert %{"token_type" => "Bearer", "expires_in" => 900, "scope" => "shop:read shop:write"} =
               tokens

      # It calls the shop as that user.
      me =
        build_conn()
        |> mcp(tokens["access_token"], call_tool("me"))
        |> json_response(200)

      assert %{"result" => %{"isError" => false, "content" => [%{"text" => text}]}} = me
      assert %{"email" => "ann@example.com", "role" => "customer"} = Jason.decode!(text)

      # And refreshes.
      refreshed =
        build_conn()
        |> token_request(%{
          "grant_type" => "refresh_token",
          "refresh_token" => tokens["refresh_token"],
          "client_id" => client["client_id"]
        })
        |> json_response(200)

      assert refreshed["refresh_token"] != tokens["refresh_token"]

      assert %{"result" => %{"isError" => false}} =
               build_conn()
               |> mcp(refreshed["access_token"], call_tool("me"))
               |> json_response(200)
    end
  end

  describe "the logs" do
    import ExUnit.CaptureLog

    test "never hold a code, a verifier or a refresh token, even at debug level", %{conn: conn} do
      user = register!()
      {:ok, client} = RegisterClient.call(%{name: "Claude", redirect_uris: [@redirect]})

      {:ok, %{code: code}} =
        AuthorizeClient.call(%{
          user_id: user.id,
          client_id: client.id,
          redirect_uri: @redirect,
          scope: "shop:read",
          code_challenge: challenge(),
          code_challenge_method: "S256"
        })

      log =
        capture_log([level: :debug], fn ->
          tokens =
            conn
            |> token_request(%{
              "grant_type" => "authorization_code",
              "code" => code,
              "code_verifier" => @verifier,
              "client_id" => client.id,
              "redirect_uri" => @redirect
            })
            |> json_response(200)

          build_conn()
          |> token_request(%{
            "grant_type" => "refresh_token",
            "refresh_token" => tokens["refresh_token"],
            "client_id" => client.id
          })
          |> json_response(200)

          send(self(), {:refresh_token, tokens["refresh_token"]})
        end)

      assert_received {:refresh_token, refresh_token}

      # The request was logged (so the test would notice a log that stayed silent)...
      assert log =~ "OAuthController.token/2"
      assert log =~ client.id

      # ...but none of its secrets are in it.
      for secret <- [code, @verifier, refresh_token] do
        refute log =~ secret
      end

      assert log =~ "[FILTERED]"
    end
  end

  describe "the token endpoint" do
    test "never lets an answer be kept", %{conn: conn} do
      conn = token_request(conn, %{"grant_type" => "authorization_code"})
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert get_resp_header(conn, "pragma") == ["no-cache"]
    end

    test "answers in RFC 6749's terms", %{conn: conn} do
      assert %{"error" => "unsupported_grant_type"} =
               conn |> token_request(%{"grant_type" => "password"}) |> json_response(400)

      assert %{"error" => "invalid_request"} = conn |> token_request(%{}) |> json_response(400)

      assert %{"error" => "invalid_request"} =
               conn
               |> token_request(%{"grant_type" => "authorization_code"})
               |> json_response(400)

      assert %{"error" => "invalid_grant"} =
               conn
               |> token_request(%{
                 "grant_type" => "authorization_code",
                 "code" => "nobody-issued-this",
                 "code_verifier" => @verifier,
                 "client_id" => "x",
                 "redirect_uri" => @redirect
               })
               |> json_response(400)

      assert %{"error" => "invalid_grant"} =
               conn
               |> token_request(%{
                 "grant_type" => "refresh_token",
                 "refresh_token" => "unknown",
                 "client_id" => "x"
               })
               |> json_response(400)
    end

    test "does not give a second set of tokens for one code", %{conn: conn} do
      user = register!()
      {:ok, client} = RegisterClient.call(%{name: "Claude", redirect_uris: [@redirect]})

      {:ok, %{code: code}} =
        AuthorizeClient.call(%{
          user_id: user.id,
          client_id: client.id,
          redirect_uri: @redirect,
          scope: "shop:read",
          code_challenge: challenge(),
          code_challenge_method: "S256"
        })

      params = %{
        "grant_type" => "authorization_code",
        "code" => code,
        "code_verifier" => @verifier,
        "client_id" => client.id,
        "redirect_uri" => @redirect
      }

      assert %{"access_token" => _} = conn |> token_request(params) |> json_response(200)
      assert %{"error" => "invalid_grant"} = conn |> token_request(params) |> json_response(400)
    end
  end

  describe "the MCP endpoint" do
    test "without a token it says where to log in", %{conn: conn} do
      conn = mcp(conn, nil, rpc("tools/list"))

      assert conn.status == 401

      assert get_resp_header(conn, "www-authenticate") == [
               ~s(Bearer resource_metadata="#{@issuer}/.well-known/oauth-protected-resource/mcp")
             ]
    end

    test "with a token that is not good, it says so", %{conn: conn} do
      for token <- ["garbage", "a.b.c", ""] do
        conn = mcp(conn, token, rpc("tools/list"))
        assert conn.status == 401, token

        if token != "" do
          assert [challenge] = get_resp_header(conn, "www-authenticate")
          assert challenge =~ ~s(error="invalid_token")
        end
      end
    end

    test "serves a token's user, as that user", %{conn: conn} do
      tokens = tokens_for(register!())
      result = conn |> mcp(tokens.access_token, rpc("tools/list")) |> json_response(200)

      names = Enum.map(result["result"]["tools"], & &1["name"])
      assert "list_products" in names and "restock_product" in names
    end

    test "an admin's token restocks; the role is the account's, not the token's", %{conn: conn} do
      admin = admin!()
      product = product!(admin, %{name: "Blue mug", stock: 3})
      tokens = tokens_for(admin)

      args = %{"admin_id" => admin.id, "product_id" => product.id, "quantity" => 4}

      result =
        conn |> mcp(tokens.access_token, call_tool("restock_product", args)) |> json_response(200)

      assert %{"result" => %{"isError" => false, "content" => [%{"text" => text}]}} = result
      assert %{"stock" => 7} = Jason.decode!(text)
    end

    test "a customer's token with the write scope still can not restock", %{conn: conn} do
      admin = admin!()
      product = product!(admin, %{stock: 3})
      customer = register!("c@example.com")
      tokens = tokens_for(customer, "shop:read shop:write")

      args = %{"admin_id" => customer.id, "product_id" => product.id, "quantity" => 4}

      result =
        conn |> mcp(tokens.access_token, call_tool("restock_product", args)) |> json_response(200)

      assert %{"result" => %{"isError" => true, "content" => [%{"text" => text}]}} = result
      assert text =~ "Admins only"
    end

    test "a token that was not given the write scope is told to ask for it", %{conn: conn} do
      admin = admin!()
      product = product!(admin)
      tokens = tokens_for(admin, "shop:read")

      args = %{"admin_id" => admin.id, "product_id" => product.id, "quantity" => 1}
      conn = mcp(conn, tokens.access_token, call_tool("restock_product", args))

      assert conn.status == 403
      assert [challenge] = get_resp_header(conn, "www-authenticate")
      assert challenge =~ ~s(error="insufficient_scope")
      assert challenge =~ ~s(scope="shop:write")
    end

    test "reading needs only the read scope, and a role change shows at once", %{conn: conn} do
      customer = register!("c@example.com")
      tokens = tokens_for(customer, "shop:read")

      report = call_tool("shop_report", %{"admin_id" => customer.id})

      assert %{"result" => %{"isError" => true}} =
               conn |> mcp(tokens.access_token, report) |> json_response(200)

      WebShop.Infrastructure.Repo.query!("UPDATE users SET role = 'admin' WHERE id = $1", [
        Ecto.UUID.dump!(customer.id)
      ])

      assert %{"result" => %{"isError" => false}} =
               build_conn() |> mcp(tokens.access_token, report) |> json_response(200)
    end

    test "a deleted account's token stops working", %{conn: conn} do
      user = register!("gone@example.com")
      tokens = tokens_for(user)

      WebShop.Infrastructure.Repo.query!("DELETE FROM users WHERE id = $1", [
        Ecto.UUID.dump!(user.id)
      ])

      assert conn |> mcp(tokens.access_token, rpc("tools/list")) |> Map.fetch!(:status) == 401
    end

    test "a web page can not use it", %{conn: conn} do
      tokens = tokens_for(register!())

      conn =
        conn
        |> put_req_header("origin", "https://evil.example")
        |> mcp(tokens.access_token, rpc("tools/list"))

      assert conn.status == 403
    end

    test "is for POST", %{conn: conn} do
      assert conn |> get("/mcp") |> Map.fetch!(:status) == 405
    end
  end
end
