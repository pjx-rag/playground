# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Playground.Repo.insert!(%Playground.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Playground.Accounts
alias Playground.Authorization
alias Playground.Organizations
alias Playground.Settings

# Setup authorization roles and permissions
IO.puts("Setting up authorization...")
Authorization.setup!()
IO.puts("Authorization setup complete!")

# Seed default themes and app settings
IO.puts("Seeding default themes...")
Settings.seed_default_themes()
IO.puts("Default themes seeded!")

IO.puts("Seeding default app settings...")
Code.require_file("seeds/app_settings.exs", __DIR__)
IO.puts("Default app settings seeded!")

IO.puts("Seeding document categories...")
Code.require_file("seeds/categories.exs", __DIR__)
IO.puts("Document categories seeded!")

# Create PJX organization
IO.puts("Creating PJX organization...")

pjx_org =
  case Organizations.get_organization_by_name("PJX") do
    nil ->
      {:ok, org} = Organizations.create_organization(%{name: "PJX"})
      IO.puts("PJX organization created!")
      org

    existing_org ->
      IO.puts("PJX organization already exists.")
      existing_org
  end

# Create admin user if it doesn't exist
admin_email = System.get_env("ADMIN_EMAIL", "admin@example.com")
admin_password = System.get_env("ADMIN_PASSWORD", "password123456")

case Accounts.get_user_by_email(admin_email) do
  nil ->
    IO.puts("Creating admin user: #{admin_email}")

    {:ok, user} =
      Accounts.register_user(%{
        email: admin_email,
        password: admin_password,
        first_name: "Admin",
        last_name: "User"
      })

    # Confirm the user immediately
    # In production releases, Machinery supervision tree may not be started,
    # so we directly update the status field instead of using transition_to
    user = Playground.Repo.update!(Ecto.Changeset.change(user, status: "confirmed"))

    # Grant admin role
    Authorization.grant_admin(user)

    # Add user to PJX organization
    Organizations.add_user_to_organization(pjx_org, user)
    IO.puts("Admin user created, confirmed, and added to PJX organization!")

  existing_user ->
    IO.puts("Admin user already exists: #{admin_email}")
    # Ensure admin role is granted
    Authorization.grant_admin(existing_user)

    # Ensure user is in PJX organization
    case Organizations.get_user_organization(existing_user) do
      nil ->
        Organizations.add_user_to_organization(pjx_org, existing_user)
        IO.puts("Admin role ensured and user added to PJX organization.")

      _org ->
        IO.puts("Admin role ensured and user already in organization.")
    end
end

IO.puts("Seeds completed!")
