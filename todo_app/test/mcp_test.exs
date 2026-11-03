defmodule TodoApp.MCPTest do
  # The todo application, used through its MCP server against the real database.
  use TodoApp.DataCase

  alias TodoApp.Interface.MCP, as: Server

  defp rpc(method, params \\ nil) do
    message = %{"jsonrpc" => "2.0", "id" => 1, "method" => method}
    message = if params, do: Map.put(message, "params", params), else: message
    {:reply, response} = Server.handle(message)
    response
  end

  defp call(name, arguments) do
    %{"result" => result} = rpc("tools/call", %{"name" => name, "arguments" => arguments})
    result
  end

  defp data(result) do
    assert result["isError"] == false, inspect(result)
    result |> get_in(["content", Access.at(0), "text"]) |> Jason.decode!()
  end

  defp read(uri) do
    %{"result" => %{"contents" => [%{"text" => text}]}} =
      rpc("resources/read", %{"uri" => uri})

    Jason.decode!(text)
  end

  defp user! do
    data(call("register_user", %{"name" => "Ann", "email" => "ann@example.com"}))
  end

  test "every exposed module is described" do
    tools = rpc("tools/list")["result"]["tools"]

    assert Enum.map(tools, & &1["name"]) ==
             ~w(achievements_of add_item complete_item create_list list_activity lists_of_owner
                open_items record_progress register_user rename_item search_lists)

    assert Enum.all?(tools, &(String.length(&1["description"]) > 10))

    for tool <- tools, {name, schema} <- tool["inputSchema"]["properties"] do
      assert schema["description"], "#{tool["name"]}.#{name} has no description"
    end
  end

  test "a whole session: register, create a list, add, complete, read it back" do
    user = user!()
    assert user["email"] == "ann@example.com"

    list = data(call("create_list", %{"owner_id" => user["id"], "name" => "Home"}))
    assert list["name"] == "Home"

    added =
      data(
        call("add_item", %{
          "list_id" => list["id"],
          "title" => "Buy milk",
          "due_date" => Date.to_iso8601(Date.add(Date.utc_today(), 3))
        })
      )

    [item] = added["items"]
    assert item["status"] == "open"

    assert [%{"title" => "Buy milk"}] = data(call("open_items", %{"list_id" => list["id"]}))

    assert %{"lists" => [%{"name" => "Home", "open" => 1, "done" => 0}], "total_lists" => 1} =
             data(call("lists_of_owner", %{"owner_id" => user["id"]}))

    done = data(call("complete_item", %{"list_id" => list["id"], "item_id" => item["id"]}))
    assert [%{"status" => "done"}] = done["items"]

    assert [] = data(call("open_items", %{"list_id" => list["id"]}))

    # The list is a resource too, by id and by owner.
    assert read("todo_list://#{list["id"]}")["items"] |> hd() |> Map.fetch!("status") == "done"

    assert %{"count" => 1, "items" => [%{"id" => id}]} =
             read("todo_list://by/owner_id/#{user["id"]}")

    assert id == list["id"]

    assert read("user://#{user["id"]}")["name"] == "Ann"

    # Progress and achievements.
    progress = data(call("record_progress", %{"owner_id" => user["id"]}))
    assert progress["completed_tasks"] == 1
    assert [%{"code" => "newbie"}] = data(call("achievements_of", %{"user_id" => user["id"]}))
  end

  test "business rules reach the client as errors it can act on" do
    user = user!()
    list = data(call("create_list", %{"owner_id" => user["id"], "name" => "Home"}))
    added = data(call("add_item", %{"list_id" => list["id"], "title" => "Once"}))
    item_id = added["items"] |> hd() |> Map.fetch!("id")
    data(call("complete_item", %{"list_id" => list["id"], "item_id" => item_id}))

    again = call("complete_item", %{"list_id" => list["id"], "item_id" => item_id})
    assert again["isError"] == true
    error = again |> get_in(["content", Access.at(0), "text"]) |> Jason.decode!()
    assert error["error"]["code"] == "precondition_failed"
    # The client is told which list it was, so it can tell the failures of several calls apart.
    assert error["error"]["entity"] == "TodoList"
    assert error["error"]["entity_id"] == list["id"]
    assert [%{"code" => "already_completed"}] = error["error"]["violations"]

    missing = call("open_items", %{"list_id" => UUID.uuid4()})
    assert missing["isError"] == true
    assert get_in(missing, ["content", Access.at(0), "text"]) =~ "list_not_found"

    bad = call("register_user", %{"name" => "Bob", "email" => "nope"})
    assert bad["isError"] == true
    assert get_in(bad, ["content", Access.at(0), "text"]) =~ "invalid_email"
  end

  describe "tags and priority" do
    setup do
      user = user!()

      %{
        user: user,
        list: data(call("create_list", %{"owner_id" => user["id"], "name" => "Home"}))
      }
    end

    test "an item has a priority and tags, and the query can filter by priority", %{list: list} do
      add = fn title, extra ->
        data(call("add_item", Map.merge(%{"list_id" => list["id"], "title" => title}, extra)))
      end

      add.("plain", %{})
      add.("urgent", %{"priority" => "high", "tags" => ["work", "today"]})
      add.("later", %{"priority" => "low"})

      all = data(call("open_items", %{"list_id" => list["id"]}))
      assert Enum.map(all, & &1["title"]) == ["plain", "urgent", "later"]

      assert %{"priority" => "normal", "tags" => []} = Enum.find(all, &(&1["title"] == "plain"))

      assert %{"priority" => "high", "tags" => ["work", "today"]} =
               Enum.find(all, &(&1["title"] == "urgent"))

      assert [%{"title" => "urgent"}] =
               data(call("open_items", %{"list_id" => list["id"], "priority" => "high"}))
    end

    test "bad priorities and tags are explained", %{list: list} do
      bad = fn extra ->
        call("add_item", Map.merge(%{"list_id" => list["id"], "title" => "x"}, extra))
      end

      assert get_in(bad.(%{"priority" => "urgent"}), ["content", Access.at(0), "text"]) =~
               "invalid_type"

      for {tags, code} <- [
            {Enum.map(1..6, &"t#{&1}"), "too_many_tags"},
            {["  "], "blank_tag"},
            {[String.duplicate("x", 21)], "tag_too_long"},
            {["a", "a"], "duplicate_tag"}
          ] do
        result = bad.(%{"tags" => tags})
        assert result["isError"] == true
        assert get_in(result, ["content", Access.at(0), "text"]) =~ code
      end
    end

    test "the schema tells a client the allowed values" do
      tool = Enum.find(rpc("tools/list")["result"]["tools"], &(&1["name"] == "add_item"))
      props = tool["inputSchema"]["properties"]
      assert props["priority"]["enum"] == ["low", "normal", "high"]
      assert props["tags"]["type"] == "array"
      assert props["tags"]["items"] == %{"type" => "string"}
    end
  end

  describe "listing" do
    setup do
      user = user!()

      for name <- ~w(Work Home Garden Garage Errands) do
        data(call("create_list", %{"owner_id" => user["id"], "name" => name}))
      end

      %{user: user}
    end

    test "lists_of_owner pages by name", %{user: user} do
      first = data(call("lists_of_owner", %{"owner_id" => user["id"], "page_size" => 2}))
      assert Enum.map(first["lists"], & &1["name"]) == ["Errands", "Garage"]
      assert %{"page" => 1, "page_size" => 2, "total_lists" => 5, "total_pages" => 3} = first

      third =
        data(call("lists_of_owner", %{"owner_id" => user["id"], "page_size" => 2, "page" => 3}))

      assert Enum.map(third["lists"], & &1["name"]) == ["Work"]
    end

    test "lists_of_owner only lists the owner's, and a page size is capped", %{user: user} do
      other = data(call("register_user", %{"name" => "Bob", "email" => "bob@example.com"}))
      data(call("create_list", %{"owner_id" => other["id"], "name" => "Bob's"}))

      mine = data(call("lists_of_owner", %{"owner_id" => user["id"], "page_size" => 5000}))
      assert mine["total_lists"] == 5
      assert mine["page_size"] == 100
    end

    test "search_lists by part of the name, with a cursor", %{user: user} do
      found = data(call("search_lists", %{"name_contains" => "GAR", "owner_id" => user["id"]}))
      assert Enum.map(found["lists"], & &1["name"]) == ["Garage", "Garden"]
      assert found["next_cursor"] == nil

      first = data(call("search_lists", %{"limit" => 2}))
      assert Enum.map(first["lists"], & &1["name"]) == ["Errands", "Garage"]
      assert is_binary(first["next_cursor"])

      second = data(call("search_lists", %{"limit" => 2, "after" => first["next_cursor"]}))
      assert Enum.map(second["lists"], & &1["name"]) == ["Garden", "Home"]

      last = data(call("search_lists", %{"limit" => 2, "after" => second["next_cursor"]}))
      assert Enum.map(last["lists"], & &1["name"]) == ["Work"]
      assert last["next_cursor"] == nil
    end

    test "typed % and _ are text, not wildcards" do
      assert %{"lists" => []} = data(call("search_lists", %{"name_contains" => "%"}))
      assert %{"lists" => []} = data(call("search_lists", %{"name_contains" => "_ome"}))
    end

    test "a bad cursor is an answer, not a crash" do
      result = call("search_lists", %{"after" => "garbage"})
      assert result["isError"] == true
      assert get_in(result, ["content", Access.at(0), "text"]) =~ "invalid_cursor"
    end

    test "a bad page is an answer too", %{user: user} do
      result = call("lists_of_owner", %{"owner_id" => user["id"], "page" => 0})
      assert result["isError"] == true
      assert get_in(result, ["content", Access.at(0), "text"]) =~ "invalid_page"
    end
  end

  describe "list_activity (a projection, read through a query)" do
    alias TodoApp.Application.Projections.TodoList.ListStats

    test "is empty until the events have been delivered, then shows the lists" do
      ListStats.subscribe()
      on_exit(&ListStats.unsubscribe/0)

      assert %{"lists" => [], "total_lists" => 0} = data(call("list_activity", %{}))

      user = user!()
      list = data(call("create_list", %{"owner_id" => user["id"], "name" => "Home"}))
      data(call("add_item", %{"list_id" => list["id"], "title" => "a"}))
      added = data(call("add_item", %{"list_id" => list["id"], "title" => "b"}))
      item = added["items"] |> List.last()
      data(call("complete_item", %{"list_id" => list["id"], "item_id" => item["id"]}))

      # Still nothing: the projection trails the lists until the outbox delivers.
      assert %{"total_lists" => 0} = data(call("list_activity", %{}))

      start_supervised!({DDD.Outbox.Poller, repo: Repo, interval_ms: 600_000})
      {:ok, _} = DDD.Outbox.Poller.poll_now()

      assert %{
               "total_lists" => 1,
               "lists" => [%{"items_added" => 2, "items_completed" => 1} = row]
             } = data(call("list_activity", %{}))

      assert row["list_id"] == list["id"]
      assert is_binary(row["last_activity_at"])
    end
  end

  test "a bad argument is explained, and an unknown id is simply not found" do
    result = call("add_item", %{"list_id" => "not-a-uuid", "title" => "x"})
    assert result["isError"] == true
    assert get_in(result, ["content", Access.at(0), "text"]) =~ "must be a uuid"

    assert %{"error" => %{"code" => -32_002}} =
             rpc("resources/read", %{"uri" => "todo_list://#{UUID.uuid4()}"})
  end

  test "resources are described and the lookups are the declared ones" do
    templates = rpc("resources/templates/list")["result"]["resourceTemplates"]

    assert Enum.map(templates, & &1["uriTemplate"]) == [
             "todo_list://{id}",
             "todo_list://by/owner_id/{owner_id}",
             "user://{id}",
             "user://by/email/{email}"
           ]
  end

  test "a read-only session cannot change anything" do
    {:ok, input} =
      StringIO.open(
        ~s({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"register_user","arguments":{"name":"Eve","email":"eve@example.com"}}}\n)
      )

    {:ok, output} = StringIO.open("")
    :ok = Server.serve(read_only: true, input: input, output: output)
    {_, written} = StringIO.contents(output)

    result = written |> Jason.decode!() |> Map.fetch!("result")
    assert result["isError"] == true
    assert get_in(result, ["content", Access.at(0), "text"]) =~ "read_only"
    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM users")
  end
end
