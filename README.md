# vicander examples

Example applications built with [vicander](https://github.com/blackuprise/vicander), a
Domain-Driven Design framework for Elixir.

| Example                | What it shows                                                                                 |
|------------------------|-----------------------------------------------------------------------------------------------|
| [`todo_app`](todo_app) | Aggregates, value objects, specifications, commands, queries, an event outbox, a read model, an MCP server and a small HTTP API |

Each example is its own Mix project. See its README for setup (they need Postgres on localhost).

```bash
cd todo_app
mix deps.get
mix test
```

Licensed under the Apache License 2.0.
