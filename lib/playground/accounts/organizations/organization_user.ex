defmodule Playground.Accounts.Organizations.OrganizationUser do
  use Ecto.Schema
  import Ecto.Changeset

  schema "organization_users" do
    belongs_to :organization, Playground.Accounts.Organizations.Organization
    belongs_to :user, Playground.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(organization_user, attrs) do
    organization_user
    |> cast(attrs, [:organization_id, :user_id])
    |> validate_required([:organization_id, :user_id])
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:organization_id, :user_id])
  end
end
