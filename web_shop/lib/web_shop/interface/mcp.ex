defmodule WebShop.Interface.MCP do
  @moduledoc """
  The shop as an MCP server, for an AI client. It mostly reads; the one thing it changes is
  stock, and only for an admin (`restock_product`). Nothing can be bought or registered through
  it, and there is no login tool.

      mix shop.mcp --email customer@shop.test           # serve on stdin/stdout
      mix shop.mcp --email admin@shop.test --read-only   # the same without the restock command
      claude mcp add shop --env SHOP_MCP_PASSWORD=... -- mix shop.mcp --email customer@shop.test

  The client acts as the user the server was started as, with the web interface's rules
  (`WebShop.Interface.MCP.Policy`): everyone signed in can see who they are (`me`) and browse
  products; a customer reads their own basket and orders; an admin also reads anyone's, the shop
  report and the pending baskets, and restocks products. `tools/list` shows all the tools
  whoever you are; a call the user may not make is refused with the reason.

  Like the web interface this calls only the application's queries, never a repository.
  """
  use DDD.MCP.Server,
    name: "web-shop",
    instructions:
      "A web shop, acting as the signed-in user. Call `me` first for your id, then " <>
        "`list_products`. A customer reads their own basket (`view_basket`) and orders " <>
        "(`orders_of_customer`) with their id as customer_id. An admin can also read any " <>
        "customer's, read `shop_report` and `pending_baskets`, and add stock with " <>
        "`restock_product` (product_id and quantity), always with their own id as admin_id.",
    commands: [
      WebShop.Application.Commands.Product.RestockProduct
    ],
    queries: [
      WebShop.Interface.MCP.Me,
      WebShop.Application.Queries.Product.ListProducts,
      WebShop.Application.Queries.Basket.ViewBasket,
      WebShop.Application.Queries.Order.OrdersOfCustomer,
      WebShop.Application.Queries.Report.ShopReport,
      WebShop.Application.Queries.Basket.PendingBaskets
    ],
    authorize: &WebShop.Interface.MCP.Policy.authorize/2
end
