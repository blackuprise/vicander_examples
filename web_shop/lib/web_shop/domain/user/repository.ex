defmodule WebShop.Domain.User.Repository do
  @moduledoc "Port: how the domain loads and saves users. The adapter is configuration."
  use DDD.Repository

  repo WebShop.Domain.User do
    find_by :email
  end

  @doc "The adapter configured for this port."
  def impl, do: :web_shop |> Application.fetch_env!(:repositories) |> Keyword.fetch!(:user)
end
