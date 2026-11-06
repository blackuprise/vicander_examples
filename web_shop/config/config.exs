import Config

config :web_shop, ecto_repos: [WebShop.Infrastructure.Repo]

# The framework needs to know the application's repo.
config :vicander, repo: WebShop.Infrastructure.Repo

# Which adapter implements each of the domain's repository ports.
config :web_shop, :repositories,
  user: WebShop.Infrastructure.User.Repository,
  product: WebShop.Infrastructure.Product.Repository,
  basket: WebShop.Infrastructure.Basket.Repository,
  order: WebShop.Infrastructure.Order.Repository

# Where each aggregate is stored, for `loads:` on a command field.
config :vicander, :repositories, [
  {WebShop.Domain.User, WebShop.Domain.User.Repository},
  {WebShop.Domain.Product, WebShop.Domain.Product.Repository},
  {WebShop.Domain.Basket, WebShop.Domain.Basket.Repository},
  {WebShop.Domain.Order, WebShop.Domain.Order.Repository}
]

config :vicander, :health,
  projections: [
    WebShop.Application.Projections.Order.DailySales,
    WebShop.Application.Projections.Basket.BasketOverview
  ]

config :web_shop, WebShop.Interface.Web.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: WebShop.Interface.Web.ErrorHTML], layout: false],
  pubsub_server: WebShop.PubSub,
  live_view: [signing_salt: "web-shop-lv-salt"]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
