defmodule Mix.Tasks.Shop.Mcp do
  @shortdoc "Serves the shop to an MCP client on stdin/stdout, as one user"
  @moduledoc """
  Serves `WebShop.Interface.MCP` to an MCP client, acting as one user:

      SHOP_MCP_PASSWORD=customer-password mix shop.mcp --email customer@shop.test
      SHOP_MCP_PASSWORD=admin-password mix shop.mcp --email admin@shop.test --read-only

  The email can also be given as `SHOP_MCP_EMAIL`. The password is only read from
  `SHOP_MCP_PASSWORD`, so it does not show in the process list; stdin is the protocol, so there
  is no prompt. `--read-only` refuses the command tools (restocking), whoever the user is.

  This is `mix vic.mcp WebShop.Interface.MCP` without the web server and the outbox poller:
  the process only answers questions and restocks (which emits no events), and the web server
  of a running shop already owns the port.
  """
  use Boundary, classify_to: WebShop
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _names} = OptionParser.parse!(args, strict: [email: :string, read_only: :boolean])
    prepare(opts)
    Mix.Tasks.Vic.Mcp.run(mcp_args(opts))
  end

  @doc false
  # The arguments of `mix vic.mcp`: the server, and `--read-only` when asked for.
  def mcp_args(opts) do
    ["WebShop.Interface.MCP"] ++ if(opts[:read_only], do: ["--read-only"], else: [])
  end

  @doc false
  # What `run/1` sets before the application starts (see `WebShop.Boot`).
  def prepare(opts) do
    Application.put_env(:web_shop, :start_web, false)
    Application.put_env(:web_shop, :start_outbox_poller, false)
    Application.put_env(:web_shop, :subscribe_handlers, false)

    if email = opts[:email], do: Application.put_env(:web_shop, :mcp_email, email)
    :ok
  end
end
