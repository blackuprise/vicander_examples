defmodule WebShop.Infrastructure.Repo do
  @moduledoc "The Ecto repo."
  use Ecto.Repo, otp_app: :web_shop, adapter: Ecto.Adapters.Postgres
end
