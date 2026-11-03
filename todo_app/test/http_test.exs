defmodule TodoApp.HTTPTest do
  # The demo HTTP API, called as a Plug (no socket) against the real database.
  use TodoApp.DataCase
  import Plug.Test
  import Plug.Conn

  alias TodoApp.Interface.HTTP

  defp request(method, path, body \\ nil) do
    conn = conn(method, path, body && Jason.encode!(body))
    conn = if body, do: put_req_header(conn, "content-type", "application/json"), else: conn
    conn = HTTP.call(conn, HTTP.init([]))
    {conn.status, Jason.decode!(conn.resp_body)}
  end

  defp list! do
    {200, user} = request(:post, "/tools/register_user", %{name: "Ann", email: "ann@example.com"})
    {200, list} = request(:post, "/tools/create_list", %{owner_id: user["id"], name: "Home"})
    list
  end

  test "lists the tools" do
    assert {200, %{"tools" => tools}} = request(:get, "/tools")
    assert "add_item" in Enum.map(tools, & &1["name"])
  end

  test "a whole session over HTTP" do
    list = list!()

    assert {200, _} = request(:post, "/tools/add_item", %{list_id: list["id"], title: "Buy milk"})

    assert {200, [%{"title" => "Buy milk"}]} =
             request(:post, "/tools/open_items", %{list_id: list["id"]})

    assert {200, %{"name" => "Home"}} = request(:get, "/resources/todo_list/#{list["id"]}")
  end

  test "a business error is a 422" do
    list = list!()

    assert {422, %{"error" => %{"code" => _}}} =
             request(:post, "/tools/add_item", %{list_id: list["id"], title: ""})
  end

  test "unknown tools and routes are a 404" do
    assert {404, %{"error" => _}} = request(:post, "/tools/nope", %{})
    assert {404, %{"error" => _}} = request(:get, "/nowhere")
  end
end
