defmodule WebShop.Interface.Web.OAuthHTML do
  @moduledoc """
  The two pages of the authorization flow: the consent page, where the user decides whether an
  app may act for them, and an error page for a request that can not be trusted enough to send
  the user back to the app.

  The app's name is whatever it called itself when it registered, so it is labelled as that, next
  to the address the user would be sent back to, which is the part that can be relied on.
  """
  use Phoenix.Component

  attr(:client_name, :string, required: true)
  attr(:redirect_host, :string, required: true)
  attr(:scopes, :list, required: true)
  attr(:fields, :map, required: true)
  attr(:email, :string, required: true)

  def consent(assigns) do
    ~H"""
    <section class="card narrow" id="consent">
      <h1>Allow access?</h1>
      <p>
        An app wants to act for <strong>{@email}</strong> in the shop.
      </p>
      <dl>
        <dt class="muted">Name given by the app</dt>
        <dd><strong>{@client_name}</strong></dd>
        <dt class="muted">After you decide, you are sent back to</dt>
        <dd><code>{@redirect_host}</code></dd>
      </dl>
      <p>It would be able to:</p>
      <ul>
        <li :for={{scope, description} <- @scopes}>
          {description} <small class="muted">({scope})</small>
        </li>
      </ul>
      <p class="muted">
        It can only do what you can do: your role in the shop still decides. You can say no.
      </p>
      <form action="/oauth/authorize" method="post" id="consent-form">
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <input :for={{name, value} <- @fields} type="hidden" name={name} value={value} />
        <button type="submit" name="decision" value="allow">Allow</button>
        <button type="submit" name="decision" value="deny" class="ghost">Deny</button>
      </form>
    </section>
    """
  end

  attr(:message, :string, required: true)

  def error(assigns) do
    ~H"""
    <section class="card narrow" id="oauth-error">
      <h1>This request can not be completed</h1>
      <p>{@message}</p>
      <p class="muted">Nothing was shared with the app. Go back to the app and try again.</p>
    </section>
    """
  end
end
