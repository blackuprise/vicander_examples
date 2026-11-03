defmodule TodoApp.Interface.HTTP do
  @moduledoc """
  The todo application over HTTP, for demonstration. It adds no logic of its own: every route
  hands the request to `TodoApp.Interface.MCP`, so the HTTP API offers exactly the same
  commands, queries and resources, validated and reported the same way.

      GET  /tools                          what can be called, with each input schema
      POST /tools/:name                    call a command or query, the JSON body is its input
      GET  /resources/:entity/*path        read an aggregate, e.g. /resources/todo_list/<id>
                                           or /resources/todo_list/by/owner_id/<owner id>

  Success is `200`, a business error (`{"error": ...}`) is `422`, an unknown tool or resource is
  `404`, and anything else is `500`.

      curl -X POST localhost:4000/tools/register_user \\
        -H 'content-type: application/json' -d '{"name":"Ann","email":"ann@example.com"}'
  """
  use Plug.Router

  alias TodoApp.Interface.MCP

  plug(:match)
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:dispatch)

  get "/tools" do
    rpc(conn, "tools/list", %{})
  end

  post "/tools/:name" do
    rpc(conn, "tools/call", %{"name" => name, "arguments" => conn.body_params})
  end

  get "/resources/:entity/*path" do
    rpc(conn, "resources/read", %{"uri" => "#{entity}://#{Enum.join(path, "/")}"})
  end

  match _ do
    send_json(conn, 404, %{"error" => %{"code" => "not_found", "message" => "No such route"}})
  end

  defp rpc(conn, method, params) do
    message = %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}

    case MCP.handle(message) do
      {:reply, %{"result" => %{"isError" => true} = result}} ->
        body = text_of(result)
        send_json(conn, if(business_error?(body), do: 422, else: 500), body)

      {:reply, %{"result" => %{"content" => _} = result}} ->
        send_json(conn, 200, text_of(result))

      {:reply, %{"result" => %{"contents" => [%{"text" => text}]}}} ->
        send_json(conn, 200, Jason.decode!(text))

      {:reply, %{"result" => result}} ->
        send_json(conn, 200, result)

      {:reply, %{"error" => error}} ->
        send_json(conn, 404, %{"error" => %{"code" => "not_found", "message" => error["message"]}})
    end
  end

  # A tool result carries its JSON as text; failures the client cannot fix are plain text.
  defp text_of(%{"content" => [%{"text" => text} | _]}) do
    case Jason.decode(text) do
      {:ok, decoded} -> decoded
      {:error, _} -> %{"error" => %{"code" => "failed", "message" => text}}
    end
  end

  defp business_error?(%{"error" => %{"code" => code}}), do: code != "failed"
  defp business_error?(_body), do: false

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
