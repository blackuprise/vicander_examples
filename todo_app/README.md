# TodoApp

A todo application built with the [`vicander`](https://github.com/blackuprise/vicander) DDD framework (`DDD.*`). It is the
framework's example and its first user: a `User` aggregate, a `TodoList` aggregate holding
`TodoItem` entities with a `Title` value object, specifications for the business rules, events
delivered through the outbox, commands, queries, a read model, and an MCP server.

## Setup

The framework is a [Hex package](https://hex.pm/packages/vicander); this example uses version
0.3.0 (`{:vicander, "~> 0.3"}` in `mix.exs`).

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
    commands/user/                register_user, record_progress, onboard_user
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

### The unit of work

Every command runs in a unit of work (`DDD.UnitOfWork`), and so does every handler delivery. It
changes nothing in how the commands are written, and a good deal in what they cost and how they
behave:

* **A list is read once and written once.** `AddItem` declares `field :list_id, :uuid, loads:
  TodoListRepository`; the framework reads the list before `execute/1` runs, and the
  `find_by_id` in `execute/1` is answered from memory. `save` only records the list. When the
  command ends it is written: one `UPDATE`, and one `INSERT` of the `ItemAdded` event, inside the
  command's transaction (`test/unit_of_work_test.exs` counts the statements).
* **`loads:` names the aggregate.** `field :list_id, :uuid, loads: TodoList`, or `loads: true` on
  a `{:ref, User}` field, which already says what it is. Where each aggregate is stored is
  configured once (`config :vicander, :repositories` in `config/config.exs`, naming the domain's
  port, whose adapter is chosen by `config :todo_app, :repositories`), so the application layer
  never names infrastructure. A list that does not exist stops the command before it does
  anything, with a business `:not_found` error that names the entity (`TodoList`), the id and the
  field (`list_id`). That replaced a hand-written `Support.load_list` and three different error
  codes (`list_not_found`, `owner_not_found`, `user_not_found`).
* **Editing the same list at once works.** `AddItem`, `CompleteItem` and `RenameItem` say
  `retry_on_conflict: 3`. When two edits overlap, the loser's write is refused (`:stale_aggregate`),
  and the command runs again on the list as the winner left it, after a short random wait. The
  rules are checked again on the fresh list: of two people completing the same item, one wins
  and the other is told it is already done. The same retry covers a deadlock
  (`:deadlock_detected`). `test/concurrent_edits_test.exs` does it on real connections.
* **`updated_at` says when a list was stored.** Operations (`add_item`, `complete_item`) no
  longer touch it; the write does, and only when something stored changed. What a command
  returns is what was stored.

One rule to know about: once a command has saved something, it cannot ask the repository for
anything but an aggregate by its id (`find_by_owner_id`, `list`, `count` raise
`DDD.UnitOfWork.PendingChangesError`), because those read the database, which does not have the
unwritten change yet. `RecordProgress` counts the user's completed items *before* it saves the
user, for that reason.

#### Chaining commands

A command can call other commands. They join its transaction and unit of work, so the chain is
written once, at the end, and either all of it happens or none of it.
`Commands.User.OnboardUser` registers a user, creates their first list and adds a welcome item:

```elixir
with {:ok, user} <- Commands.User.RegisterUser.call(%{name: name, email: email}),
     {:ok, list} <- Commands.TodoList.CreateList.call(%{owner_id: user.id, name: "Getting started"}),
     {:ok, list} <- Commands.TodoList.AddItem.call(%{list_id: list.id, title: "Welcome to your list"}) do
  {:ok, %{user: user, list: list}}
end
```

None of it is in the database while the chain runs, yet `CreateList` finds the user it was given
and `AddItem` the list: both read by id, and the unit of work holds what was saved. At the end
there is one `INSERT` per table.

A chain stops working when a step *queries* after an earlier one saved something. `RecordProgress`
looks a user's lists up with `find_by_owner_id`, so `CompleteItem` followed by `RecordProgress` in
one command raises `PendingChangesError`, and the completion is rolled back with it
(`test/chaining_test.exs` does exactly that). There are two ways to connect such steps:

* **An event**, as the application does: `CompleteItem` emits `ItemCompleted`, and once it is
  committed the outbox runs `AchievementTracker`, which calls `RecordProgress` (see
  "Achievements"). The second step is its own transaction, and may be retried on its own.
* **Two commands one after the other**, from whoever drives them (the HTTP handler, a script): the
  first commits, so the second's queries see its work. You give up all-or-nothing across the two.

The rule of thumb: chain commands that need each other's *ids*; connect commands that need each
other's *queries* with an event, or run them in sequence.

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
  each other: the second write fails with `:stale_aggregate` (optimistic locking) when the
  handler's unit of work is written, the outbox retries that delivery, and the recount then sees
  both. (`RecordProgress` does not use `retry_on_conflict` here: inside a delivery it joins the
  delivery's transaction, and a command in an open transaction is never retried; the outbox is
  the retry.)
