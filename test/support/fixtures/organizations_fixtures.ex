defmodule Tasky.OrganizationsFixtures do
  @moduledoc """
  Test helpers for creating organizations via `Tasky.Organizations`.

  `default_organization/0` and `default_class/0` are what keep the rest of the
  suite honest: because a teacher's organization and a student's class decide
  who can see whom, every teacher/student pair a test builds has to end up in the
  same organization or the test would fail on the fail-closed rule rather than on
  what it means to assert.
  """

  alias Tasky.Classes
  alias Tasky.Organizations
  alias Tasky.Organizations.Organization
  alias Tasky.Repo

  @default_name "Testorganisation"
  @default_class_name "Testklasse"

  def organization_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{name: "Organisation #{System.unique_integer([:positive])}"})

    # `:system` is the trusted in-library actor and passes `authorize_admin/1`.
    {:ok, organization} = Organizations.create_organization(:system, attrs)
    organization
  end

  @doc """
  The shared organization every fixture defaults into, created on first use.

  Memoised in the process dictionary because `user_fixture/1` asks for it on
  every call and the test pool has no headroom (`pool_size` equals ExUnit's
  `max_cases`). A test runs in its own process and its own sandbox transaction,
  so the cache is naturally per-test; a miss just re-queries and finds the same
  row.
  """
  def default_organization do
    memoize(:default_organization, fn ->
      case Repo.get_by(Organization, slug: Classes.Class.slugify(@default_name)) do
        nil -> organization_fixture(%{name: @default_name})
        organization -> organization
      end
    end)
  end

  @doc "The shared class inside `default_organization/0`, created on first use."
  def default_class do
    memoize(:default_class, fn ->
      case Classes.get_class_by_slug(Classes.Class.slugify(@default_class_name)) do
        nil ->
          {:ok, class} =
            Classes.create_class(:system, %{
              name: @default_class_name,
              organization_id: default_organization().id
            })

          class

        class ->
          class
      end
    end)
  end

  defp memoize(key, fun) do
    case Process.get({__MODULE__, key}) do
      nil ->
        value = fun.()
        Process.put({__MODULE__, key}, value)
        value

      value ->
        value
    end
  end
end
