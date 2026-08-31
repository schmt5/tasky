ExUnit.start()

# Seed the shared organization/class before the sandbox goes manual, so the
# rows are committed and every test finds them instead of inserting its own.
# See `Tasky.OrganizationsFixtures.seed_defaults!/0` for what that fixes.
Tasky.OrganizationsFixtures.seed_defaults!()

Ecto.Adapters.SQL.Sandbox.mode(Tasky.Repo, :manual)
