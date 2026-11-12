defmodule WebShop.Interface.Web.OAuthController do
  @moduledoc """
  The shop as an OAuth authorization server for the MCP endpoint (only in `:builtin` mode; with
  an external server these routes answer `404`, except the description of the MCP endpoint).

      GET  /.well-known/oauth-protected-resource/mcp   what the MCP endpoint is and who to log in at (RFC 9728)
      GET  /.well-known/oauth-authorization-server     the endpoints below (RFC 8414)
      GET  /oauth/jwks                                 the keys that verify the access tokens
      POST /oauth/register                             an app registers itself (RFC 7591)
      GET  /oauth/authorize                            the user logs in (the shop's own login) and decides
      POST /oauth/authorize                            ... Allow or Deny
      POST /oauth/token                                a code or a refresh token for tokens

  Everything here is a thin shell over the application's commands and queries. What matters is
  in them (and in the domain): this decides only how a result is shown. The one rule it keeps is
  where a refusal goes. A request whose app or redirect address can not be trusted gets an error
  page and never a redirect, because a redirect to an unchecked address is how a code would
  reach the wrong app. Any other refusal goes back to the (checked) address with `error` and
  `state`, and every answer to the app names the issuer (RFC 9207).
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias WebShop.Application.Commands.OAuth.{
    AuthorizeClient,
    ExchangeCode,
    RefreshGrant,
    RegisterClient
  }

  alias WebShop.Application.OAuth.{Access, Endpoints}
  alias WebShop.Application.Queries.OAuth.{GetClient, Jwks, ResourceMetadata, ServerMetadata}
  alias WebShop.Interface.Web.{Auth, OAuthHTML}

  plug(:own_server_only when action != :resource_metadata)

  # ── Metadata ────────────────────────────────────────────────────────────

  def resource_metadata(conn, _params) do
    {:ok, document} = ResourceMetadata.call(%{})
    json(conn, document)
  end

  def server_metadata(conn, _params) do
    {:ok, document} = ServerMetadata.call(%{})
    json(conn, document)
  end

  def jwks(conn, _params) do
    {:ok, keys} = Jwks.call(%{})
    json(conn, keys)
  end

  # ── Registration (RFC 7591) ─────────────────────────────────────────────

  def register(conn, params) do
    case RegisterClient.call(%{
           name: params["client_name"],
           redirect_uris: params["redirect_uris"]
         }) do
      {:ok, client} ->
        conn
        |> put_status(201)
        |> no_store()
        |> json(%{
          client_id: client.id,
          client_name: client.name,
          redirect_uris: client.redirect_uris,
          grant_types: ["authorization_code", "refresh_token"],
          response_types: ["code"],
          token_endpoint_auth_method: "none"
        })

      {:error, error} ->
        {status, body} = registration_error(error)
        conn |> put_status(status) |> no_store() |> json(body)
    end
  end

  defp registration_error(%DDD.Error{kind: :infrastructure}),
    do: {500, %{error: "server_error", error_description: "could not register the app"}}

  defp registration_error(%DDD.Error{} = error) do
    redirect_problem? = Enum.any?(error.violations, &(&1.field == :redirect_uris))

    {400,
     %{
       error: if(redirect_problem?, do: "invalid_redirect_uri", else: "invalid_client_metadata"),
       error_description: first_message(error)
     }}
  end

  # ── The token endpoint (RFC 6749 §3.2) ──────────────────────────────────

  def token(conn, %{"grant_type" => "authorization_code"} = params) do
    result =
      ExchangeCode.call(%{
        code: params["code"],
        code_verifier: params["code_verifier"],
        client_id: params["client_id"],
        redirect_uri: params["redirect_uri"]
      })

    respond_tokens(conn, result)
  end

  def token(conn, %{"grant_type" => "refresh_token"} = params) do
    respond_tokens(
      conn,
      RefreshGrant.call(%{refresh_token: params["refresh_token"], client_id: params["client_id"]})
    )
  end

  def token(conn, %{"grant_type" => _other}),
    do:
      token_error(conn, 400, "unsupported_grant_type", "use authorization_code or refresh_token")

  def token(conn, _params),
    do: token_error(conn, 400, "invalid_request", "grant_type is required")

  defp respond_tokens(conn, {:ok, tokens}), do: conn |> no_store() |> json(tokens)

  # The loser of two requests with the same code: the code is spent.
  defp respond_tokens(conn, {:error, %DDD.Error{code: :stale_aggregate}}),
    do: token_error(conn, 400, "invalid_grant", "the code or token was already used")

  defp respond_tokens(conn, {:error, %DDD.Error{kind: :infrastructure}}),
    do: token_error(conn, 500, "server_error", "try again later")

  defp respond_tokens(conn, {:error, %DDD.Error{code: :validation_failed} = error}),
    do: token_error(conn, 400, "invalid_request", first_message(error))

  defp respond_tokens(conn, {:error, %DDD.Error{} = error}),
    do: token_error(conn, 400, "invalid_grant", error.message)

  defp token_error(conn, status, code, description) do
    conn
    |> put_status(status)
    |> no_store()
    |> json(%{error: code, error_description: description})
  end

  # ── Authorization (the user's part) ─────────────────────────────────────

  def authorize(conn, params) do
    with {:ok, client, redirect_uri} <- trusted(params),
         :ok <- check_request(params, redirect_uri, conn) do
      case Auth.current_user(get_session(conn)) do
        nil -> redirect(conn, to: login_path(conn))
        user -> consent(conn, user, client, redirect_uri, params)
      end
    else
      {:untrusted, message} ->
        error_page(conn, message)

      {:refuse, redirect_uri, code, description} ->
        go_back(conn, redirect_uri, params, %{"error" => code, "error_description" => description})
    end
  end

  def decide(conn, params) do
    with {:ok, _client, redirect_uri} <- trusted(params),
         %{} = user <- Auth.current_user(get_session(conn)) do
      case params["decision"] do
        "allow" -> allow(conn, user, redirect_uri, params)
        _ -> go_back(conn, redirect_uri, params, %{"error" => "access_denied"})
      end
    else
      {:untrusted, message} -> error_page(conn, message)
      nil -> error_page(conn, "You were logged out while deciding. Start again from the app.")
    end
  end

  defp allow(conn, user, redirect_uri, params) do
    result =
      AuthorizeClient.call(%{
        user_id: user.id,
        client_id: params["client_id"],
        redirect_uri: redirect_uri,
        scope: params["scope"],
        code_challenge: params["code_challenge"],
        code_challenge_method: params["code_challenge_method"]
      })

    case result do
      {:ok, %{code: code}} ->
        go_back(conn, redirect_uri, params, %{"code" => code})

      {:error, %DDD.Error{code: code} = error} when code in [:invalid_scope, :invalid_request] ->
        go_back(conn, redirect_uri, params, %{
          "error" => to_string(code),
          "error_description" => error.message
        })

      {:error, %DDD.Error{} = error} ->
        go_back(conn, redirect_uri, params, %{
          "error" => "server_error",
          "error_description" => error.message
        })
    end
  end

  # The app and the address are the part nothing may be sent to before it is right.
  defp trusted(params) do
    client_id = params["client_id"]

    with true <- is_binary(client_id),
         {:ok, client} <- GetClient.call(%{client_id: client_id}),
         {:ok, redirect_uri} <- redirect_uri(client, params["redirect_uri"]) do
      {:ok, client, redirect_uri}
    else
      _ ->
        {:untrusted,
         "The app is not known, or the address it asked to be sent back to is not one it registered."}
    end
  end

  # An address that is given is an exact match; one that is left out is fine for an app that has just the one.
  defp redirect_uri(client, uri) when is_binary(uri) do
    if uri in client.redirect_uris, do: {:ok, uri}, else: :error
  end

  defp redirect_uri(%{redirect_uris: [only]}, nil), do: {:ok, only}
  defp redirect_uri(_client, _uri), do: :error

  # The rest of the request. A fault here is the app's, so it is told, at its checked address.
  defp check_request(params, redirect_uri, _conn) do
    cond do
      params["response_type"] != "code" ->
        {:refuse, redirect_uri, "unsupported_response_type", "response_type must be code"}

      not Access.challenge?(params["code_challenge"]) or params["code_challenge_method"] != "S256" ->
        {:refuse, redirect_uri, "invalid_request",
         "PKCE is required: code_challenge with method S256"}

      match?({:error, _}, Access.parse_scope(params["scope"])) ->
        {:refuse, redirect_uri, "invalid_scope", "unknown scope"}

      true ->
        :ok
    end
  end

  defp consent(conn, user, client, redirect_uri, params) do
    {:ok, asked} = Access.parse_scope(params["scope"])

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("content-security-policy", "frame-ancestors 'none'")
    |> put_view(html: OAuthHTML)
    |> put_layout(html: {WebShop.Interface.Web.Layouts, :app})
    |> assign(:current_user, user)
    |> assign(:basket_quantity, Auth.basket_quantity(user))
    |> assign(:page_title, "Allow access?")
    |> render(:consent,
      client_name: client.name,
      redirect_host: host(redirect_uri),
      scopes: Enum.filter(Access.describe(), fn {scope, _} -> scope in asked end),
      email: user.email,
      fields: %{
        "client_id" => client.client_id,
        "redirect_uri" => redirect_uri,
        "scope" => Enum.join(asked, " "),
        "state" => params["state"] || "",
        "code_challenge" => params["code_challenge"],
        "code_challenge_method" => params["code_challenge_method"],
        "response_type" => "code"
      }
    )
  end

  defp error_page(conn, message) do
    conn
    |> put_status(400)
    |> put_view(html: OAuthHTML)
    |> put_layout(html: {WebShop.Interface.Web.Layouts, :app})
    |> assign(:current_user, Auth.current_user(get_session(conn)))
    |> assign(:basket_quantity, 0)
    |> assign(:page_title, "Request refused")
    |> render(:error, message: message)
  end

  # ── Shared ──────────────────────────────────────────────────────────────

  # Back to the app, at the address already checked, naming the issuer and echoing `state`.
  defp go_back(conn, redirect_uri, params, extra) do
    query =
      extra
      |> Map.put("iss", Endpoints.issuer())
      |> Map.put("state", params["state"])
      |> Enum.reject(fn {_, value} -> value in [nil, ""] end)
      |> URI.encode_query()

    url = redirect_uri |> URI.parse() |> URI.append_query(query) |> URI.to_string()

    conn
    |> put_resp_header("referrer-policy", "no-referrer")
    |> redirect(external: url)
  end

  defp login_path(conn) do
    back = "/oauth/authorize?" <> conn.query_string
    "/login?" <> URI.encode_query(%{"return_to" => back})
  end

  defp host(uri) do
    case URI.parse(uri) do
      %URI{host: host, port: port, scheme: scheme} when scheme in ["http", "https"] ->
        if port in [80, 443, nil], do: host, else: "#{host}:#{port}"

      _ ->
        uri
    end
  end

  defp first_message(%DDD.Error{violations: [%{field: field, message: message} | _]}),
    do: "#{field} #{message}"

  defp first_message(%DDD.Error{message: message}), do: message

  defp no_store(conn) do
    conn |> put_resp_header("cache-control", "no-store") |> put_resp_header("pragma", "no-cache")
  end

  # In external mode the shop is not an authorization server: these routes do not exist.
  defp own_server_only(conn, _opts) do
    if Endpoints.builtin?() do
      conn
    else
      conn |> put_status(404) |> json(%{error: "not_found"}) |> halt()
    end
  end
end
