# Demo data for development: an admin, a customer and a few products. Safe to run twice.
alias WebShop.Application.Commands.Product.AddProduct
alias WebShop.Application.Commands.User.RegisterUser
alias WebShop.Domain.User.Repository, as: UserRepository

ensure = fn attrs ->
  case UserRepository.impl().find_by_email(attrs.email) do
    [user | _] -> user
    [] -> RegisterUser.call!(attrs)
  end
end

admin = ensure.(%{name: "Admin", email: "admin@shop.test", password: "admin-password", role: :admin})
ensure.(%{name: "Casey Customer", email: "customer@shop.test", password: "customer-password"})

if WebShop.Domain.Product.Repository.impl().count() == {:ok, 0} do
  for {name, description, price, stock} <- [
        {"Espresso beans 1kg", "Dark roast, whole beans", 2450, 40},
        {"Pour-over kettle", "Gooseneck, 1L, stainless", 4900, 12},
        {"Ceramic mug", "350 ml, dishwasher safe", 1200, 80},
        {"Hand grinder", "Burr grinder with steel handle", 6500, 4},
        {"Paper filters (100)", "Size 02", 600, 150},
        {"Milk frother", "Battery powered whisk", 1500, 25},
        {"Travel tumbler", "Keeps drinks hot for 6 hours", 2800, 3},
        {"Tea sampler", "Eight loose-leaf teas", 3200, 18}
      ] do
    AddProduct.call!(%{admin_id: admin.id, name: name, description: description, price_cents: price, stock: stock})
  end
end

IO.puts("Seeded. Admin: admin@shop.test / admin-password, customer: customer@shop.test / customer-password")
