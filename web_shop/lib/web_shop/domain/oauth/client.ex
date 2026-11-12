defmodule WebShop.Domain.OAuth.Client do
  @moduledoc """
  Aggregate: an app that asks to act for a shop user (an AI client, say), registered with the
  addresses it may be sent back to. Public clients only: there is no client secret, and the
  proof that the app that asks for a token is the one that asked for the code is PKCE.

  The name is whatever the app said when it registered, so the consent page shows it as
  "name given by the app" next to the address, which is what can be relied on.
  """
  use DDD.Aggregate

  alias WebShop.Domain.OAuth.Client.Specs

  aggregate do
    description "An app registered to act for shop users"

    identity :id, :uuid
    field :name, :string, required: true, description: "The name the app gave itself"

    field :redirect_uris, {:array, :string},
      required: true,
      description: "Where it may be sent back"

    invariant Specs.NameValid, on: :name
    invariant Specs.RedirectUrisAllowed, on: :redirect_uris
  end
end
