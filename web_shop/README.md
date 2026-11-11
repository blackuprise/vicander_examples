# WebShop

A small web shop built with the [`vicander`](https://github.com/blackuprise/vicander) DDD framework
and Phoenix LiveView. Customers log in, browse and search products, fill a basket and place orders.
Admins add products, restock them and read a report (orders today, pending baskets, revenue, stock).

## Run it

Postgres is needed on `localhost:5432` (user and password `postgres`; `docker compose up -d --wait`
starts one). Like `todo_app`, it uses the [vicander](https://hex.pm/packages/vicander) Hex package,
version 0.3.0 (`{:vicander, "~> 0.3"}` in `mix.exs`).

```bash
mix deps.get
mix ecto.setup        # creates the database, migrates, seeds demo data
mix run --no-halt     # http://localhost:4000
mix test              # needs Postgres; `mix test --cover` enforces 90%
```

Seeded logins (development only): `admin@shop.test` / `admin-password` and
`customer@shop.test` / `customer-password`. Make another admin with
`mix shop.create_admin NAME EMAIL PASSWORD`; there is no way to become one from the web.

## Pages

| Path | Who | What |
|---|---|---|
| `/login`, `/register` | guests | log in, create a customer account |
| `/` | users | browse and search products, add to basket |
| `/basket`, `/orders` | users | review the basket and place an order; past orders |
| `/admin/products` | admins | add products, restock |
| `/admin/report` | admins | orders and revenue today and for 7 days, pending baskets, low stock (refreshes every 5s) |

## MCP: the shop for an AI client

The shop can be used by an AI client (Claude Code, Claude Desktop, any MCP client). It mostly
reads; the one thing it changes is stock, and only for an admin. Nothing can be bought or
registered through it. It **acts as one user, with the rules of the web interface**:

| tool | who may call it |
|---|---|
| `me` | everyone signed in: your id, name, email, role (the other tools need your id) |
| `list_products` | everyone signed in |
| `view_basket`, `orders_of_customer` | a customer, for their own id; an admin, for anyone's |
| `shop_report`, `pending_baskets` | admins only, with their own id as `admin_id` |
| `restock_product` | admins only, with their own id as `admin_id`, a `product_id` and a `quantity` |

```bash
SHOP_MCP_PASSWORD=customer-password mix shop.mcp --email customer@shop.test   # stdin/stdout
SHOP_MCP_PASSWORD=admin-password mix shop.mcp --email admin@shop.test --read-only   # no restocking

claude mcp add shop --env SHOP_MCP_PASSWORD=customer-password -- \
  mix shop.mcp --email customer@shop.test
```

`--read-only` refuses the command tool whoever the user is. A restock is the `RestockProduct`
command: it checks the admin role again itself, so the policy only adds that `admin_id` must be
the signed-in user.

The server signs in with `--email` (or `SHOP_MCP_EMAIL`) and `SHOP_MCP_PASSWORD` on the first
call, through the application's `Authenticate` query. The password is an environment variable,
never an argument, so it is not in the process list. Only the user's id is kept: every call asks
the application for the user again, so a changed role or a deleted account takes effect at once,
as on the web. A refused call says why (`Admins only.`), and `tools/list` shows every tool to
everyone. Passwords, registration and login are not offered at all.

`mix shop.mcp` starts the application without the web server and the outbox poller, so it runs
next to a shop that is already up on port 4000 (restocking emits no events, so nothing waits for
the poller). The code is `interface/mcp.ex` (what is offered), `interface/mcp/policy.ex` (who may
call what) and `interface/mcp/me.ex`; like the web interface it calls the application's commands
and queries only.

## How it is built

Four layers, enforced at compile time by `boundary` and one module per file:

```
domain/          User (+Password), Product, Basket (+BasketItem), Order (+OrderLine), specs, events, ports
application/     commands/ queries/ projections/ authorize.ex
infrastructure/  Postgres adapters, one per port
interface/web/   endpoint, router, auth, LiveViews: calls the application only
interface/mcp*   the read-only MCP server and who may call what: calls the application only
```

* **Checkout** (`CheckOut`) is one command and one unit of work: it reads the basket and products,
  reserves stock (a product refuses more than it has), places the order and empties the basket.
  Everything is written together or not at all, and `retry_on_conflict` handles two buyers racing
  for the last unit.
* **Reports** read two projections fed by events through the outbox: `DailySales` (`OrderPlaced`)
  and `BasketOverview` (basket events; a basket with `item_count > 0` is *pending*). They trail
  reality by a few seconds. Product counts are read directly.
* **Authorization** is in the application layer (`Authorize.admin/1`): admin commands and queries
  take the acting admin's id and check the role, so hiding a button is never the only protection.
  Registration passes name, email and password only, so a form cannot choose a role.
* **Passwords** are checked by the `Password` value object (8+ characters) and stored as PBKDF2
  hashes. Login answers the same for an unknown email and a wrong password.
* **No asset build.** The Phoenix and LiveView JS is served from `deps/`, and the CSS is one file
  in `priv/static`.

## Things to know

* The framework logs every command and query, with its parameters, at debug level. The password
  fields are `sensitive: true`, so they are left out of those lines (nothing filters the text
  afterwards); the other parameters, such as the email, are logged. Dev logs at `info`; keep
  production at `info` or above. `SQL=1` logs SQL with its parameters, the password hash among
  them: only for throwaway data.
* The session cookie holds only the user id; every page load asks the application for the user.
* Money is whole cents. A basket line keeps the name and price from when it was added.
