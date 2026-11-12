import Config

# ── OAuth for the MCP endpoint ────────────────────────────────────────────
#
# SHOP_BASE_URL            the shop's public address (the OAuth issuer, and the base of the MCP
#                          resource). https in production; http://localhost:4000 by default.
# SHOP_OAUTH_ISSUER        set it and the shop stops being its own authorization server: it only
#                          validates the tokens of that server (Keycloak, Auth0, ...).
#   SHOP_OAUTH_AUDIENCE    ... which audience a token must carry (default: the MCP resource URL)
#   SHOP_OAUTH_JWKS_URI    ... where its signing keys are (default: from the issuer's metadata)
# SHOP_JWT_PRIVATE_KEY     the PEM of the EC P-256 key the shop signs its tokens with (required
#                          in production in builtin mode). SHOP_JWT_PRIVATE_KEY_PREVIOUS is the
#                          one rotated away from: still published, so its tokens stay valid.
unescape_pem = fn pem -> String.replace(pem, "\\n", "\n") end

if base_url = System.get_env("SHOP_BASE_URL") do
  config :web_shop, :oauth, base_url: base_url
end

if issuer = System.get_env("SHOP_OAUTH_ISSUER") do
  external =
    Enum.reject(
      [
        issuer: issuer,
        audience: System.get_env("SHOP_OAUTH_AUDIENCE"),
        jwks_uri: System.get_env("SHOP_OAUTH_JWKS_URI")
      ],
      fn {_key, value} -> is_nil(value) end
    )

  config :web_shop, :oauth,
    mode: :external,
    verifier: WebShop.Infrastructure.OAuth.ExternalVerifier,
    external: external
end

if config_env() == :prod do
  base_url =
    System.get_env("SHOP_BASE_URL") ||
      raise "environment variable SHOP_BASE_URL is missing, e.g. https://shop.example.com"

  unless String.starts_with?(base_url, "https://") do
    raise "SHOP_BASE_URL must be an https address in production, got: #{base_url}"
  end

  # The shop signs its own tokens unless an external server does the authorizing.
  unless System.get_env("SHOP_OAUTH_ISSUER") do
    private_key =
      System.get_env("SHOP_JWT_PRIVATE_KEY") ||
        raise "environment variable SHOP_JWT_PRIVATE_KEY is missing (an EC P-256 private key in PEM form)"

    keys = [private_key, System.get_env("SHOP_JWT_PRIVATE_KEY_PREVIOUS")]

    config :web_shop, :oauth,
      private_keys: keys |> Enum.reject(&is_nil/1) |> Enum.map(unescape_pem)
  end

  database_url =
    System.get_env("DATABASE_URL") ||
      raise "environment variable DATABASE_URL is missing, e.g. ecto://USER:PASS@HOST/DATABASE"

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "environment variable SECRET_KEY_BASE is missing (generate one with `mix phx.gen.secret`)"

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :web_shop, WebShop.Infrastructure.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  config :web_shop, WebShop.Interface.Web.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    server: true,
    secret_key_base: secret_key_base

  config :logger, :default_handler, level: :info
end
