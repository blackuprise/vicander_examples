defmodule WebShop.Interface.MCP.Policy do
  @moduledoc """
  Who the MCP client is, and what that user may call. The same rules as the web interface: a
  customer reads their own basket and orders, an admin reads anyone's and the reports.

  An MCP server over stdio is one process for one client, so the session user is the one the
  server was started as. The first tool call signs in with `SHOP_MCP_EMAIL` (or the `--email`
  of `mix shop.mcp`) and `SHOP_MCP_PASSWORD`, through the application's `Authenticate` query;
  the password is read from the environment, not an argument, so it is not in the process list.

  Only the user's id is kept. Every call asks the application for the user again, so a role
  that changed or an account that went away takes effect at once, as it does on the web (see
  `WebShop.Interface.Web.Auth`).
  """
  alias WebShop.Application.Queries.User.{Authenticate, GetUser}

  alias WebShop.Application.OAuth.Access

  @key {__MODULE__, :user_id}
  @context_key {__MODULE__, :context}

  # The tools that change something. Everything else only reads.
  @write_tools ~w(restock_product)

  @doc """
  The `authorize:` function of `WebShop.Interface.MCP`: `:ok`, or `{:error, reason}`.

  Over HTTP the `context` is what the transport learned from the access token (`:user_id`,
  `:role`, `:scopes`), read from the account a moment ago; over stdio it is empty and the user is
  the one the server was started as. The context is also kept for the tool that runs next in
  this process, which is how `me` knows who is asking (a tool is not handed the context).
  """
  def authorize(tool, arguments, context) do
    Process.put(@context_key, context)

    case context do
      %{user_id: id, role: role} -> check(tool, %{id: id, role: role}, arguments)
      _ -> authorize(tool, arguments)
    end
  end

  @doc "Authorize a call made by the user a stdio server was started as."
  def authorize(tool, arguments) do
    with {:ok, user} <- stdio_user(), do: check(tool, user, arguments)
  end

  @doc """
  The scope a request needs, for `DDD.MCP.HTTP`'s `authorize_request:`: `:ok`, or
  `{:error, {:insufficient_scope, scope}}`, which becomes a `403` telling the client to ask the
  user for more. Reading needs `shop:read`, and the tools that change something `shop:write`.
  Only a call of a tool needs a scope; the protocol messages around it do not.
  """
  def required_scope(%{"method" => "tools/call", "params" => %{"name" => name}}, %{scopes: scopes})
      when is_binary(name) do
    needed = Access.required_scope(if name in @write_tools, do: :write, else: :read)
    if needed in scopes, do: :ok, else: {:error, {:insufficient_scope, needed}}
  end

  def required_scope(_message, _context), do: :ok

  # Everyone signed in.
  defp check("me", _user, _arguments), do: :ok
  defp check("list_products", _user, _arguments), do: :ok

  # A customer's own, or anyone's for an admin.
  defp check(tool, user, arguments) when tool in ["view_basket", "orders_of_customer"] do
    if user.role == :admin or arguments["customer_id"] == user.id,
      do: :ok,
      else: {:error, "You can only read your own basket and orders (customer_id #{user.id})."}
  end

  # Admins only, as themselves. (The commands and queries check the role again, from the id.)
  defp check(tool, user, arguments)
       when tool in ["shop_report", "pending_baskets", "restock_product"] do
    cond do
      user.role != :admin -> {:error, "Admins only."}
      arguments["admin_id"] != user.id -> {:error, "Pass your own id as admin_id (#{user.id})."}
      true -> :ok
    end
  end

  defp check(_tool, _user, _arguments), do: {:error, "Not allowed."}

  @doc "The signed-in user (a map with `:id`, `:name`, `:email`, `:role`), or `{:error, reason}`."
  def current_user do
    case Process.get(@context_key) do
      %{user_id: id} -> fetch(id)
      _ -> stdio_user()
    end
  end

  defp stdio_user do
    with {:ok, id} <- session_id(), do: fetch(id)
  end

  @doc "Sign in as `email` with `password` and remember the user's id."
  def sign_in(email, password) do
    with {:ok, user} <- Authenticate.call(%{email: email, password: password}) do
      :persistent_term.put(@key, user.id)
      {:ok, user}
    end
  end

  @doc "Forget the session user (for tests)."
  def sign_out, do: :persistent_term.erase(@key)

  defp session_id do
    case :persistent_term.get(@key, nil) do
      nil -> sign_in_from_environment()
      id -> {:ok, id}
    end
  end

  defp sign_in_from_environment do
    email = Application.get_env(:web_shop, :mcp_email) || System.get_env("SHOP_MCP_EMAIL")
    password = System.get_env("SHOP_MCP_PASSWORD")

    if blank?(email) or blank?(password) do
      {:error,
       "Not signed in: start the server with SHOP_MCP_EMAIL and SHOP_MCP_PASSWORD " <>
         "(mix shop.mcp --email EMAIL)."}
    else
      case sign_in(email, password) do
        {:ok, user} -> {:ok, user.id}
        {:error, _} -> {:error, "Sign-in failed: wrong SHOP_MCP_EMAIL or SHOP_MCP_PASSWORD."}
      end
    end
  end

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""

  defp fetch(id) do
    case GetUser.call(%{id: id}) do
      {:ok, user} -> {:ok, user}
      _ -> {:error, "Your account no longer exists."}
    end
  end
end
