alias Playground.{Repo, Accounts.User, Connectors.ConnectorOrganization, Files.Category}
import Ecto.Query

IO.puts("\n👥 Users:")
users = Repo.all(from u in User, select: {u.id, u.email})
case users do
  [] -> IO.puts("   No users found")
  users -> Enum.each(users, fn {id, email} -> IO.puts("   [#{id}] #{email}") end)
end

IO.puts("\n🔌 Connector Organizations:")
connectors = Repo.all(ConnectorOrganization) |> Repo.preload(:connector)
case connectors do
  [] -> IO.puts("   No connector organizations found")
  connectors -> Enum.each(connectors, fn c ->
    IO.puts("   [#{c.id}] #{if c.connector, do: c.connector.name, else: "unknown"} - #{c.status}")
  end)
end

IO.puts("\n📚 Categories:")
categories = Repo.all(from c in Category, select: c.slug, order_by: c.display_order)
case categories do
  [] -> IO.puts("   No categories found - need to run seeds!")
  categories -> IO.puts("   #{length(categories)} categories: #{Enum.join(categories, ", ")}")
end

IO.puts("")
