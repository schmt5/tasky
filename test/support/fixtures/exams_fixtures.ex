defmodule Tasky.ExamsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Tasky.Exams` context.
  """

  import Tasky.AccountsFixtures

  alias Tasky.Exams

  @doc """
  Valid attributes for enrolling a guest into an exam.
  """
  def valid_enrollment_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      "firstname" => "Max",
      "lastname" => "Muster",
      "email" => "max.muster@example.com"
    })
  end

  @doc """
  Generate an exam.

  Options:

    * `:scope` - the teacher scope owning the exam; a fresh teacher is
      created when omitted
    * `:status` - `"draft"` (default), `"open"`, or any later status such as
      `"running"`/`"finished"`; the exam is moved through the session
      lifecycle accordingly
    * `:participation_mode` - `"anonymous"` (default, so existing tests keep
      exercising the self-enrolment path) or `"assigned"`
    * `:attrs` - attributes passed to `Exams.create_exam/2`
  """
  def exam_fixture(opts \\ []) do
    scope =
      Keyword.get_lazy(opts, :scope, fn ->
        user_scope_fixture(user_fixture(%{role: "teacher"}))
      end)

    attrs =
      opts
      |> Keyword.get(:attrs, %{})
      |> Enum.into(%{
        name: "Test Prüfung",
        content: %{"type" => "doc", "content" => []}
      })

    {:ok, exam} = Exams.create_exam(scope, attrs)
    participation_mode = Keyword.get(opts, :participation_mode, "anonymous")

    case Keyword.get(opts, :status, "draft") do
      "draft" ->
        exam

      status ->
        {:ok, exam} = Exams.open_exam_session(scope, exam, participation_mode)

        steps =
          case status do
            "open" -> []
            "running" -> ~w(running)
            "finished" -> ~w(running finished)
            "archived" -> ~w(running finished archived)
          end

        Enum.reduce(steps, exam, fn s, e ->
          {:ok, e} = Exams.update_exam_status(scope, e, s)
          e
        end)
    end
  end

  @doc """
  Assign a logged-in student to the given exam.
  """
  def assigned_submission_fixture(exam, user) do
    scope = user_scope_fixture(Tasky.Accounts.get_user!(exam.teacher_id))
    {:ok, submission} = Exams.assign_student(scope, exam, user.id)
    submission
  end

  @doc """
  Enroll a guest submission into the given exam.
  """
  def exam_submission_fixture(exam, attrs \\ %{}) do
    {:ok, submission} = Exams.create_exam_submission(exam, valid_enrollment_attrs(attrs))
    submission
  end
end
