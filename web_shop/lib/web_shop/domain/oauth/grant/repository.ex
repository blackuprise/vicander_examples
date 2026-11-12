defmodule WebShop.Domain.OAuth.Grant.Repository do
  @moduledoc "Port: how the domain loads and saves grants, and finds one by the hash of a secret."
  use DDD.Repository

  repo WebShop.Domain.OAuth.Grant do
    find_by :code_hash
    find_by :refresh_hash
    find_by :previous_refresh_hash
  end

  @doc "The adapter configured for this port."
  def impl, do: :web_shop |> Application.fetch_env!(:repositories) |> Keyword.fetch!(:oauth_grant)
end
