defmodule TaskyWeb.SebDerivationFailureTest do
  @moduledoc """
  What happens when the server cannot work out the SEB Config Key it would be
  checking against.

  `Tasky.Exams.SebConfigKey` raises by design rather than emit a key it cannot
  vouch for. Unwrapped, that raise reached `Plug` and became a **500** — on the
  exam page, on every autosave `PUT` (which `assets/js/react/api.js` retries
  forever, so the editor would sit on "nicht gespeichert") and inside the
  LiveView mount, for every participant at once. The kill switch could not help,
  because `observe` derives the key too.

  The decision taken instead: a bug of ours never ends a graded exam.
  Enforcement degrades to `observe`, nobody is verified, nobody is blocked, and
  the cockpit says so in red.

  The break used here is `seb_allow_files: nil`, which finds no clause in
  `SebConfig.files/1`. It stands in for any exception on the derivation path —
  the one the `raise` was actually written for is a settings map that grows a
  float. It cannot be reached through the database (the column is `NOT NULL`),
  which is also why these tests work on in-memory structs at the two decision
  points rather than through a request: those two functions are the only places
  that can turn a derivation failure into a locked-out class.
  """
  use TaskyWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams
  alias Tasky.Exams.Exam
  alias Tasky.Exams.ExamSubmission
  alias TaskyWeb.SebGuard

  defp healthy_exam(enforcement) do
    %Exam{
      id: 1,
      seb_enabled: true,
      seb_enforcement: enforcement,
      seb_allow_files: false,
      seb_quit_password: "PRZN-9XXN-79Z",
      seb_admin_password: "SSMW6X9PVV54GAN8SDNLLNE69D",
      seb_accepted_config_keys: []
    }
  end

  defp broken_exam(enforcement),
    do: %Exam{healthy_exam(enforcement) | seb_allow_files: nil}

  defp submission, do: %ExamSubmission{exam_token: "tok-abcdef"}

  describe "derivation_error/1" do
    test "is nil while the key can be derived" do
      assert SebGuard.derivation_error(healthy_exam("enforce")) == nil
    end

    test "carries the exception message once it cannot" do
      assert SebGuard.derivation_error(broken_exam("enforce")) =~ "SebConfig.files/1"
    end

    test "says nothing about an exam that does not require SEB" do
      # Nothing is ever derived for it, so there is nothing to report.
      exam = %Exam{broken_exam("enforce") | seb_enabled: false}

      assert SebGuard.derivation_error(exam) == nil
    end
  end

  describe "the effective mode" do
    test "enforce degrades to observe when the key cannot be derived" do
      assert SebGuard.mode(healthy_exam("enforce")) == :enforce
      assert SebGuard.mode(broken_exam("enforce")) == :observe
    end

    test "the teacher's stored choice is left alone" do
      # Degrading is a runtime decision, not a rewrite: enforcement takes effect
      # again by itself the moment the derivation works.
      exam = broken_exam("enforce")

      assert SebGuard.mode(exam) == :observe
      assert exam.seb_enforcement == "enforce"
    end

    test "observe is unaffected — it never blocked anyone anyway" do
      assert SebGuard.mode(broken_exam("observe")) == :observe
    end
  end

  describe "checking a request" do
    test "a real SEB is let through rather than 500ing the exam" do
      # Every rejection the plug makes is a `{:error, _}` from here, so this is
      # the assertion that the participant sees their exam and not a 500.
      log =
        capture_log(fn ->
          assert SebGuard.check(
                   broken_exam("enforce"),
                   submission(),
                   [{"x-safeexambrowser-configkeyhash", String.duplicate("a", 64)}],
                   nil
                 ) == {:ok, :unverified}
        end)

      # Loud in the log, silent for the participant.
      assert log =~ "SEB Config Key derivation failed"
    end

    test "letting them through is not the same as vouching for them" do
      # `:unverified` is what keeps the 12-hour session stamp from being written
      # and keeps the cockpit's "verifiziert" count honest.
      capture_log(fn ->
        assert {:ok, :unverified} =
                 SebGuard.check(
                   broken_exam("enforce"),
                   submission(),
                   [{"x-safeexambrowser-configkeyhash", "whatever"}],
                   nil
                 )
      end)
    end

    test "a request with no hash at all never reaches the derivation" do
      # Short-circuited in `verdict/4`, so a plain browser costs nothing and
      # produces no alarm — it is simply not in SEB.
      assert capture_log(fn ->
               assert SebGuard.check(broken_exam("enforce"), submission(), [], nil) ==
                        {:ok, :unverified}
             end) == ""
    end

    test "the verdict itself names the failure for the cockpit" do
      capture_log(fn ->
        assert SebGuard.verdict(broken_exam("enforce"), submission(), "abc", nil) ==
                 {:error, :undecidable}
      end)
    end
  end

  describe "the cockpit banner" do
    test "names the failure and says the exam keeps running" do
      html =
        render_component(&TaskyWeb.ExamComponents.seb_derivation_alert/1,
          message: "no function clause matching in Tasky.Exams.SebConfig.files/1"
        )

      assert html =~ "Die SEB-Prüfung ist ausgefallen"
      assert html =~ "normal weiter"
      assert html =~ "Aufsicht im Raum"
      assert html =~ "SebConfig.files/1"
    end

    test "is absent while everything derives", %{conn: conn} do
      teacher = user_fixture(%{role: "teacher"})
      scope = user_scope_fixture(teacher)
      exam = exam_fixture(scope: scope, status: "running")

      {:ok, exam} =
        exam
        |> Ecto.Changeset.change(%{seb_enabled: true, seb_quit_password: "PRZN-9XXN-79Z"})
        |> Tasky.Repo.update()

      {:ok, exam} = Exams.set_seb_enforcement(:system, exam, "enforce")

      {:ok, _view, html} = conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/cockpit")

      refute html =~ "seb-derivation-error"
    end
  end
end
