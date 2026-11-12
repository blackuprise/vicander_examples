# WebShop

A small web shop built with the [`vicander`](https://github.com/blackuprise/vicander) DDD framework
and Phoenix LiveView. Customers log in, browse and search products, fill a basket and place orders.
Admins add products, restock them and read a report (orders today, pending baskets, revenue, stock).

It is also **used by AI clients** through an MCP server (Claude Code, Claude Desktop, any MCP
client), locally over stdio or remotely over HTTP, where the shop is its own OAuth 2.1
authorization server or trusts an external one. See [MCP](#mcp-the-shop-for-an-ai-client).

## Run it

Postgres is needed on `localhost:5432` (user and password `postgres`; `docker compose up -d --wait`
starts one). It uses the [vicander](https://hex.pm/packages/vicander) Hex package, version 0.4.0
(`{:vicander, "~> 0.4"}` in `mix.exs`), whose `DDD.MCP.HTTP` serves the MCP endpoint (below).

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
| `/oauth/authorize` | users | the consent page an AI app sends you to: what it asks for, Allow or Deny ([below](#over-http-with-oauth)) |

## MCP: the shop for an AI client

The shop can be used by an AI client (Claude Code, Claude Desktop, any MCP client), locally over
stdio or remotely over HTTP with OAuth (below). It mostly reads; the one thing it changes is
stock, and only for an admin. Nothing can be bought or registered through it. It **acts as one
user, with the rules of the web interface**:

| tool | who may call it |
|---|---|
| `me` | everyone signed in: your id, name, email, role (the other tools need your id) |
| `list_products` | everyone signed in |
| `view_basket`, `orders_of_customer` | a customer, for their own id; an admin, for anyone's |
| `shop_report`, `pending_baskets` | admins only, with their own id as `admin_id` |
| `restock_product` | admins only, with their own id as `admin_id`, a `product_id` and a `quantity` |

### Over stdio, as one user

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
everyone. Passwords, registration and login are not offered as tools.

`mix shop.mcp` starts the application without the web server, so it runs next to a shop that is
already up on port 4000. The outbox poller and the read-model handlers run, so the reports stay
up to date; next to a running shop the two pollers share the outbox (events are claimed with a
lease, so each is delivered once).

The code is `interface/mcp.ex` (what is offered), `interface/mcp/policy.ex` (who may call what),
`interface/mcp/auth.ex` (a bearer token to a user, over HTTP) and `interface/mcp/me.ex`. Like the
web interface it calls the application's commands and queries only.

### Over HTTP, with OAuth

The same server is also at `POST /mcp`, for many users at once, each as themselves, with no
password in an environment variable. A client that connects is sent through OAuth 2.1 (the MCP
specification's authorization):

```bash
claude mcp add --transport http shop http://localhost:4000/mcp
```

1. The first call has no token and gets `401` with `WWW-Authenticate: Bearer resource_metadata="..."`.
2. The client reads that document (RFC 9728), then the authorization server's (RFC 8414), and
   registers itself (`POST /oauth/register`, RFC 7591).
3. It opens `/oauth/authorize` in the user's browser. Not logged in? The shop's **own login** comes
   first, then back to the **consent page**: the app's name (labelled as given by the app), the
   address the user goes back to, and the scopes in plain words. Allow or Deny.
4. The code goes back to the app, with `state` and `iss`. It trades it, with its PKCE verifier,
   at `POST /oauth/token` for a 15 minute access token (a signed JWT) and a refresh token.
5. Every `/mcp` call carries `Authorization: Bearer <token>`.

The routes. Apart from the user's part (`/oauth/authorize`), none uses the cookie session: callers
send tokens, not cookies.

| route | |
|---|---|
| `POST /mcp` | the MCP endpoint (`DDD.MCP.HTTP`): one JSON-RPC message per request, a bearer token on each |
| `GET /.well-known/oauth-protected-resource/mcp` | which authorization server to log in at (always served) |
| `GET /.well-known/oauth-authorization-server` | that server's endpoints and what it supports |
| `GET /oauth/jwks` | the public keys that verify its access tokens |
| `POST /oauth/register` | an app registers itself |
| `GET`, `POST /oauth/authorize` | the user's part: log in, consent page, Allow or Deny (the browser session and CSRF apply here) |
| `POST /oauth/token` | a code or a refresh token for tokens |

The last five answer `404` when an external server does the authorizing.

What a token allows is its **scopes narrowed by the account's role**, and the role is always read
from the database, never from the token:

| scope | lets the app |
|---|---|
| `shop:read` (the default) | call the read tools |
| `shop:write` | call `restock_product` (and the user still has to be an admin) |

A call that needs a scope the token lacks gets `403` with `error="insufficient_scope"`, so a
client can ask the user for more. A token for another audience, issuer, or one that has expired
is `401`.

**Secrets.** Authorization codes (60 seconds, single use) and refresh tokens (30 days) are stored
only as SHA-256 hashes. Refresh tokens rotate on every use; presenting a replaced one, or a code
that was already used, means it leaked, and the whole grant is revoked. Access tokens are JWTs
signed with ES256; the public keys are at `/oauth/jwks`. Clients are public (no secret) and PKCE
`S256` is required. Redirect addresses are an exact match and must be `https` or on `localhost`.

**Configuration** (`config/runtime.exs`):

| variable | |
|---|---|
| `SHOP_BASE_URL` | the shop's public address; the OAuth issuer, and the base of the `/mcp` resource. Required in production, and `https` there. |
| `SHOP_JWT_PRIVATE_KEY` | the signing key, an EC P-256 private key in PEM form. Required in production (the app does not start without it); development makes one and keeps it in `priv/dev_jwt_key.pem` (git-ignored). |
| `SHOP_JWT_PRIVATE_KEY_PREVIOUS` | the key you rotated away from: still published, so its tokens stay valid until they expire. |

```bash
openssl ecparam -name prime256v1 -genkey -noout   # a key to put in SHOP_JWT_PRIVATE_KEY
```

**With another authorization server.** The shop can leave the authorizing to Keycloak, Auth0,
Entra or any OpenID Connect provider and only validate its tokens. Set `SHOP_OAUTH_ISSUER` and the
`/oauth/*` routes disappear (`404`), and `/mcp` trusts that server instead:

| variable | |
|---|---|
| `SHOP_OAUTH_ISSUER` | the provider's issuer URL. Its metadata (`/.well-known/openid-configuration`) must name the same issuer. |
| `SHOP_OAUTH_AUDIENCE` | the audience a token must carry; default is the `/mcp` address. |
| `SHOP_OAUTH_JWKS_URI` | where its keys are; default is what its metadata says. |

The provider must issue JWT access tokens whose audience is the `/mcp` address (or what you set),
with the user's verified `email`; an `RS256`, `ES256`, `PS256` or `EdDSA` signature is accepted,
nothing else. The shop finds the **account with that email** (no account is made, and an email the
provider did not verify is refused) and applies that account's role. For Keycloak: a client for the
AI app, an *audience* mapper that adds the `/mcp` address, and the `email` scope. The keys are read
over `https`, kept for an hour, and fetched again (no more than once a minute) when a token names a
key the shop does not know, so a rotation is picked up.

**What this does not do.** Dynamic registration is open to anyone and has no rate limit, and
clients that never finish are not cleaned up. There is no page where a user lists and revokes the
apps they allowed (a grant can be revoked in the database; its access tokens end within 15
minutes). Client ID Metadata Documents are not supported, only dynamic registration and apps
listed in `config :web_shop, :oauth, clients: [...]`. There is no CORS, so a client running in a
browser tab can not use it. A provider that lets users change their own email without verifying it
can hand out access to someone else's shop account: only use one that does not.

The code: the `Client` and `Grant` aggregates and the token ports are in `domain/oauth/`, the
commands (`RegisterClient`, `AuthorizeClient`, `ExchangeCode`, `RefreshGrant`, `RevokeGrant`) and
queries in `application/`, the signing key, the JWT code and the external server's verifier in
`infrastructure/oauth/`, and the thin controller, the consent page and the policy in `interface/`.

## How it is built

Four layers, enforced at compile time by `boundary` and one module per file:

```
domain/          User (+Password), Product, Basket (+BasketItem), Order (+OrderLine), specs, events, ports
application/     commands/ queries/ projections/ authorize.ex
infrastructure/  Postgres adapters, one per port
interface/web/   endpoint, router, auth, LiveViews: calls the application only
interface/mcp*   the MCP server, over stdio and HTTP, and who may call what: calls the application only
                 (OAuth lives in each layer: domain/oauth, application/*/oauth, infrastructure/oauth)
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
  Registration passes name, email and password only, so a form cannot choose a role. An AI client
  goes through the same rules, with the scopes of its token narrowing them (see MCP above).
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
* **Run it somewhere other than `http://localhost:4000`? Set `SHOP_BASE_URL`.** An access token
  names the issuer and the audience (`<base>/mcp`), and the shop checks both against that
  address, never against the request. With the wrong one every token is refused.
* The key that signs access tokens is made on first start in development (`priv/dev_jwt_key.pem`,
  git-ignored). Deleting it makes a new one, and the access tokens already issued stop working (the
  apps refresh and carry on); in production it is `SHOP_JWT_PRIVATE_KEY` and the app does not
  start without it.
* Money is whole cents. A basket line keeps the name and price from when it was added.
