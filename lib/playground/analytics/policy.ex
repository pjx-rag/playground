defmodule Playground.Analytics.Policy do
  @moduledoc """
  Authorization policy for PhoenixAnalytics dashboard access.
  """
  @behaviour Bodyguard.Policy
  alias Playground.Authorization

  @doc """
  Only admin users can view analytics dashboard.
  Requires admin:system permission.
  """
  def authorize(:view_analytics, user, _params) do
    if Authorization.admin?(user) do
      :ok
    else
      :error
    end
  end
end
