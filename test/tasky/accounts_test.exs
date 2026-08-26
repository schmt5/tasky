defmodule Tasky.AccountsTest do
  use Tasky.DataCase

  alias Tasky.Accounts

  import Tasky.AccountsFixtures
  import Tasky.ClassesFixtures
  import Tasky.OrganizationsFixtures
  alias Tasky.Accounts.{User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email_and_password(user.email, "hello world!")
    end
  end

  describe "register_user/2 — the invitation decides the role" do
    setup do
      %{class: class_fixture(), organization: organization_fixture()}
    end

    test "a class link creates a student in that class", %{class: class} do
      {:ok, user} =
        Accounts.register_user(valid_user_attributes(), {:class, class})

      assert user.role == "student"
      assert user.class_id == class.id
      # A student's organization is derived from their class, never stored.
      assert user.organization_id == nil
    end

    test "an organization link creates a teacher in that organization", %{
      organization: organization
    } do
      {:ok, user} =
        Accounts.register_user(valid_user_attributes(), {:organization, organization})

      assert user.role == "teacher"
      assert user.organization_id == organization.id
      assert user.class_id == nil
    end

    test "role, class and organization in the params are ignored", %{class: class} do
      other = organization_fixture()
      other_class = class_fixture()

      {:ok, user} =
        Accounts.register_user(
          valid_user_attributes(%{
            role: "admin",
            is_teacher: true,
            class_id: other_class.id,
            organization_id: other.id
          }),
          {:class, class}
        )

      # This is the regression test that matters: before invitations, a crafted
      # submit could set `is_teacher` and `class_id` and so walk into a foreign
      # organization as a teacher. None of those fields is castable any more.
      assert user.role == "student"
      assert user.class_id == class.id
      assert user.organization_id == nil
    end

    test "there is no registration without an invitation" do
      assert_raise FunctionClauseError, fn ->
        Accounts.register_user(valid_user_attributes(), nil)
      end

      assert_raise FunctionClauseError, fn ->
        Accounts.register_user(valid_user_attributes(), {:organization, nil})
      end
    end

    test "requires email to be set", %{class: class} do
      {:error, changeset} = Accounts.register_user(%{}, {:class, class})

      assert %{email: ["darf nicht leer sein"]} = errors_on(changeset)
    end

    test "validates email when given", %{class: class} do
      {:error, changeset} = Accounts.register_user(%{email: "not valid"}, {:class, class})

      assert %{email: ["muss ein @-Zeichen enthalten und darf keine Leerzeichen haben"]} =
               errors_on(changeset)
    end

    test "validates maximum values for email for security", %{class: class} do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_user(%{email: too_long}, {:class, class})
      assert "darf maximal 160 Zeichen lang sein" in errors_on(changeset).email
    end

    test "validates email uniqueness", %{class: class} do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{email: email}, {:class, class})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} =
        Accounts.register_user(%{email: String.upcase(email)}, {:class, class})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users with password and auto-confirms", %{class: class} do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email), {:class, class})
      assert user.email == email
      assert user.hashed_password != ""
      assert is_struct(user.confirmed_at, DateTime)
    end

    test "requires password", %{class: class} do
      {:error, changeset} =
        Accounts.register_user(
          %{email: unique_user_email(), firstname: "A", lastname: "B"},
          {:class, class}
        )

      assert %{password: ["darf nicht leer sein"]} = errors_on(changeset)
    end

    test "validates password length", %{class: class} do
      {:error, changeset} =
        Accounts.register_user(
          %{
            email: unique_user_email(),
            firstname: "A",
            lastname: "B",
            password: "short"
          },
          {:class, class}
        )

      assert %{password: ["muss zwischen 8 und 72 Zeichen lang sein"]} = errors_on(changeset)
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end
end
