# TodoApp

A todo application built with the [`vicander`](https://github.com/blackuprise/vicander) DDD framework (`DDD.*`). It is the
framework's example and its first user: a `User` aggregate, a `TodoList` aggregate holding
`TodoItem` entities with a `Title` value object, specifications for the business rules, events
delivered through the outbox, commands, queries, a read model, and an MCP server.

## Setup

The framework is a [Hex package](https://hex.pm/packages/vicander)
(`{:vicander, "~> 0.1"}`).

Postgres is needed on `localhost:5432` (user and password `postgres`). If you have none, start
one with Docker:

```bash
docker compose up -d --wait    # Postgres 17; `docker compose down -v` removes it and its data
```

```bash
mix deps.get
mix test          # creates and migrates the test database; needs Postgres on localhost
mix ecto.setup    # the dev database
```

What the framework needs from an application:

* `config :vicander, repo: TodoApp.Infrastructure.Repo` (`config/config.exs`), so commands,
  queries, handlers and the `mix vic.*` tasks know the repo.
* `{DDD.Supervisor, handlers: [...]}` in the supervision tree (`TodoApp.Boot`), which starts the
  event bus, subscribes the handlers and runs the outbox poller.
* The outbox tables, generated once with `mix vic.gen.outbox_migration`, and one migration per
  aggregate with `mix vic.gen.migration TodoApp.Domain.TodoList`.
* `import_deps: [:vicander]` in `.formatter.exs`, so the DSL (`field :name, :string`) formats
  without parentheses.

Test output is quiet by default (warnings and errors only). `LOG=1 mix test` shows the whole
flow, and `SQL=1` adds the SQL queries.

```elixir
alias TodoApp.Application.{Commands, Queries}

{:ok, user} = Commands.User.RegisterUser.call(%{name: "Ann", email: "ann@example.com"})
{:ok, list} = Commands.TodoList.CreateList.call(%{owner_id: user.id, name: "Home"})
{:ok, list} = Commands.TodoList.AddItem.call(%{list_id: list.id, title: "Buy milk"})
{:ok, _} = Commands.TodoList.AddItem.call(%{list_id: list.id, title: "Call Bob", priority: :high, tags: ["phone"]})
{:ok, open} = Queries.TodoList.OpenItems.call(%{list_id: list.id, priority: :high})
{:ok, page} = Queries.TodoList.ListsOfOwner.call(%{owner_id: user.id, page_size: 10})
{:ok, found} = Queries.TodoList.SearchLists.call(%{name_contains: "ho"})
```

An item has a `priority` (`:low`, `:normal` or `:high`, an enum) and `tags` (a list of strings, at
most 5, short and distinct: the `TagsWithinLimit` value spec). The queries show the listing
features: `lists_of_owner` is a numbered page (`DDD.Page`, with totals), `search_lists` is a cursor
slice (`DDD.Slice`, no totals, stable while lists are added) filtered with `{:ilike, ...}`, and
`list_activity` pages the `ListStats` read model. The repository port declares `list/1`, `page/1`,
`slice/1` and `count/1` as optional callbacks, which the Postgres adapters implement.

The same application is available to an AI client: `mix compile && mix vic.mcp
TodoApp.Interface.MCP` serves all six commands, the five queries, and the lists and users as
resources (see the framework's README). `mix vic.mcp TodoApp.Interface.MCP --read-only` offers only
the queries and resources.

### Layers

Four layers, each grouped by sub-domain (one per aggregate), one module per file, and the file
path is the module name (`TodoApp.Domain.TodoList.Specs.ItemExists` is
`lib/todo_app/domain/todo_list/specs/item_exists.ex`). An aggregate root sits beside the folder
of its children:

```
lib/todo_app/
  domain/                         TodoApp.Domain.*           depends on nothing of the app
    todo_list.ex                  the TodoList aggregate root
    todo_list/                    todo_item, title, repository (the port),
                                  events/ (item_added, item_completed), specs/ (12 rules)
    user.ex                       the User aggregate root
    user/                         achievement, achievements (the catalog), repository (the port),
                                  events/ (achievement_earned), specs/ (6 rules)
  application/                    TodoApp.Application.*      depends on domain
    commands/todo_list/           create_list, add_item, complete_item, rename_item
    commands/user/                register_user, record_progress
    queries/todo_list/            open_items, lists_of_owner, search_lists, list_activity
    queries/user/                 achievements_of
    projections/todo_list/        list_stats (a read model fed by events, read by list_activity)
    handlers/user/                achievement_tracker (reacts to events by running a command)
  infrastructure/                 TodoApp.Infrastructure.*   implements the domain's ports
    todo_list/repository.ex       Ecto/Postgres adapters, one per port
    user/repository.ex
    event_logger.ex               shared, so it stays at the top
  interface/                       TodoApp.Interface.*        calls application, reads domain
    mcp.ex                        the MCP server: what the todo app offers to an AI client
```

A command lives in the folder of the aggregate it acts on, so
`TodoApp.Application.Commands.TodoList.RenameItem` is `.../commands/todo_list/rename_item.ex`.
The sub-domains do not depend on each other: aggregates refer to each other by id only, and
use cases that span both (like `RecordProgress`) live in the application layer.

The application layer never names an adapter. It calls the domain's port, and configuration
chooses the adapter:

```elixir
# config/config.exs
config :todo_app, :repositories,
  todo_list: TodoApp.Infrastructure.TodoList.Repository,
  user: TodoApp.Infrastructure.User.Repository

# in a command
TodoListRepository.impl().save(list)     # the port; today the Postgres adapter
```

So swapping an adapter (the in-memory repository in a test, another database) is a config
change, and the commands and the domain do not change. `test/ports_test.exs` runs real
commands against in-memory adapters to prove it. `test/architecture_test.exs` fails if
the domain mentions the application or infrastructure, if the application mentions the
infrastructure, if the interface mentions the infrastructure, if one sub-domain mentions the
other, if a command, query or handler is outside the folder of an aggregate, or if a file holds
more than one module. It reads the source as text.

The real call graph is checked at compile time by [`boundary`](https://hex.pm/packages/boundary)
(`compilers: [:boundary] ++ Mix.compilers()` in `mix.exs`), so a violation is a compile warning
(an error with `mix compile --warnings-as-errors`, which CI should use). Each layer has a root module:

* `TodoApp.Domain` depends on nothing of the app, may not call Ecto or Postgrex, and exports just
  its public modules (the specifications stay internal).
* `TodoApp.Application` depends on `TodoApp.Domain`.
* `TodoApp.Interface` (the MCP server) depends on `TodoApp.Domain` and `TodoApp.Application`.
  Nothing depends on it.
* `TodoApp.Infrastructure` (the Postgres adapters and `TodoApp.Infrastructure.Repo`) depends on
  `TodoApp.Domain`.
* `TodoApp` is the composition root (`TodoApp.Boot` starts the repo and `DDD.Supervisor`), the
  only place that knows the application and infrastructure layers.

The framework is another application, so `DDD.*` is not a boundary here: the rules above are
about the application's own layers. Every module of the app must belong to a boundary. The
framework itself has no layers to check.

### The HTTP API (demo)

`TodoApp.Interface.HTTP` has no logic of its own: it passes each request to the MCP server, so it
offers the same commands, queries and resources. It is built on `plug` and `bandit` only, has no
authentication, and so should stay on localhost.

Start it (it needs the dev database, see Setup):

```bash
mix run --no-halt        # listens on http://localhost:4000
```

The port is `config :todo_app, http_port: 4000`; `config :todo_app, start_http: false` turns the
server off (the tests do).

| Route                              | What it does                                         |
|------------------------------------|------------------------------------------------------|
| `GET /tools`                       | lists every command and query with its input schema  |
| `POST /tools/:name`                | calls a command or query, the JSON body is its input |
| `GET /resources/:entity/*path`     | reads an aggregate, e.g. `/resources/todo_list/<id>` |

A full session (copy the `id` from each response into the next call):

```bash
H='content-type: application/json'

curl localhost:4000/tools                                        # what can be called

curl -X POST localhost:4000/tools/register_user -H "$H" \
  -d '{"name":"Ann","email":"ann@example.com"}'                  # -> the user, with its id
curl -X POST localhost:4000/tools/create_list -H "$H" \
  -d '{"owner_id":"<user id>","name":"Home"}'                    # -> the list, with its id
curl -X POST localhost:4000/tools/add_item -H "$H" \
  -d '{"list_id":"<list id>","title":"Call Bob","priority":"high","tags":["phone"]}'
curl -X POST localhost:4000/tools/open_items -H "$H" \
  -d '{"list_id":"<list id>","priority":"high"}'                 # a query

curl localhost:4000/resources/todo_list/<list id>                # one list
curl localhost:4000/resources/todo_list/by/owner_id/<user id>    # all lists of a user
```

Success is `200`, a business error (`{"error": {"code": ..., "message": ...}}`, such as a blank
title) is `422`, an unknown tool, resource or route is `404`, and anything else is `500`. Run
`curl localhost:4000/tools` for the exact tool names and fields.

### The MCP server

The same application can be served to an AI client (Claude Code, Claude Desktop, or any MCP client)
over stdio. It offers the six commands and five queries as tools, and the lists and users as
resources (`todo_list://<id>`, `todo_list://by/owner_id/<owner id>`). A resource shows every field,
including a user's email.

```bash
mix compile && mix vic.mcp TodoApp.Interface.MCP               # serve on stdin/stdout
mix vic.mcp TodoApp.Interface.MCP --read-only                  # queries and resources only
```

The server needs Postgres and the dev database (`mix ecto.setup`), and must run from this
directory.

**Claude Code**, from `todo_app/`:

```bash
claude mcp add todo -- mix vic.mcp TodoApp.Interface.MCP
```

**Any other client** takes a command, arguments and a working directory in its MCP settings, for
example:

```json
{
  "mcpServers": {
    "todo": {
      "command": "mix",
      "args": ["vic.mcp", "TodoApp.Interface.MCP"],
      "cwd": "/path/to/vicander_examples/todo_app"
    }
  }
}
```

Then ask the client something like "Register Ann (ann@example.com), create a list called Home for
her and add an item 'Buy milk'". To check the server without a client, use the MCP Inspector:
`npx @modelcontextprotocol/inspector mix vic.mcp TodoApp.Interface.MCP`. See the framework's
README for what a client sees.

### Achievements

Users earn achievements for completed tasks (`lib/todo_app/domain/user/achievements.ex`):

| Achievement | Earned when        |
|-------------|--------------------|
| `newbie`    | 1 task completed   |
| `beginner`  | 10 tasks completed |
| `performer` | 30 tasks completed |

* **Rules are specs.** `TodoApp.Domain.User.Achievements` is a catalog of `{code, spec}`; the thresholds
  all reuse one `CompletedTasksAtLeast` spec. Adding an achievement is one catalog line.
* **`User` is the aggregate.** It holds `completed_tasks` and `achievements` (value objects).
  `User.record_progress/2` *sets* the count (never lowers it), awards what is newly earned and
  emits `AchievementEarned`. Two invariants keep it valid: no duplicates, and nothing held
  that the catalog says was not earned.
* **Event driven.** Completing an item emits `ItemCompleted`; once the outbox delivers it,
  `TodoApp.Application.Handlers.User.AchievementTracker` runs the `RecordProgress` command, which recounts the user's
  completed items from their lists. The handler runs in a transaction with its delivery record,
  so the saved user and the `AchievementEarned` events commit together; and because it
  recounts, running it twice would be a no-op anyway.
* **Concurrent events.** Two events for one user handled at the same instant no longer overwrite
  each other: the second save fails with `:stale_aggregate` (optimistic locking), the outbox
  retries that delivery, and the recount then sees both.
