# WebShop

A small web shop built with the [`vicander`](https://github.com/blackuprise/vicander) DDD framework
and Phoenix LiveView. Customers log in, browse and search products, fill a basket and place orders.
Admins add products, restock them and read a report (orders today, pending baskets, revenue, stock).

## Run it

Postgres is needed on `localhost:5432` (user and password `postgres`; `docker compose up -d --wait`
starts one). Like `todo_app`, this example uses the unreleased unit of work and `loads:`, so
`mix.exs` points at a checkout of the framework (`{:vicander, path: "../../vicander"}`).

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

## How it is built

Four layers, enforced at compile time by `boundary` and one module per file:

```
domain/          User (+Password), Product, Basket (+BasketItem), Order (+OrderLine), specs, events, ports
application/     commands/ queries/ projections/ authorize.ex
infrastructure/  Postgres adapters, one per port
interface/web/   endpoint, router, auth, LiveViews: calls the application only
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

* The framework logs command parameters at debug level, passwords included. Dev logs at `info`;
  keep production at `info` or above.
* The session cookie holds only the user id; every page load asks the application for the user.
* `hex.audit` currently reports advisories on the transitive `ecto` and `decimal` packages with no
  patched release available; update when one ships.
* Money is whole cents. A basket line keeps the name and price from when it was added.
