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

# Setup authorization roles and permissions
IO.puts("Setting up authorization...")
Authorization.setup!()
IO.puts("Authorization setup complete!")

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

    # Confirm the user immediately using state machine
    {:ok, user} =
      Machinery.transition_to(
        user,
        Playground.Accounts.User,
        "confirmed",
        %{}
      )

    # Grant admin role
    Authorization.grant_admin(user)
    IO.puts("Admin user created and confirmed!")

  existing_user ->
    IO.puts("Admin user already exists: #{admin_email}")
    # Ensure admin role is granted
    Authorization.grant_admin(existing_user)
    IO.puts("Admin role ensured for existing user.")
end

IO.puts("Seeds completed!")
