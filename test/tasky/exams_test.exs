defmodule Tasky.ExamsTest do
  use Tasky.DataCase, async: false

  import Tasky.ExamsFixtures

  alias Tasky.Exams

  defp enrollment_attrs, do: valid_enrollment_attrs()

  defp teacher_scope(exam) do
    Tasky.Accounts.Scope.for_user(Tasky.Accounts.get_user!(exam.teacher_id))
  end

  defp sample_doc(text) do
    %{
      "type" => "doc",
      "content" => [
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}
      ]
    }
  end

  describe "create_exam_submission/2" do
    test "enrolls when the exam is open" do
      exam = exam_fixture(status: "open")

      assert {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())
      assert submission.firstname == "Max"
      assert submission.exam_token
      refute submission.submitted
    end

    test "enrolls when the exam is already running" do
      exam = exam_fixture(status: "running")

      assert {:ok, _submission} = Exams.create_exam_submission(exam, enrollment_attrs())
    end

    test "rejects enrollment for draft and finished exams" do
      assert {:error, :exam_not_open} =
               Exams.create_exam_submission(exam_fixture(status: "draft"), enrollment_attrs())

      assert {:error, :exam_not_open} =
               Exams.create_exam_submission(exam_fixture(status: "finished"), enrollment_attrs())
    end
  end

  describe "update_exam_submission_content/2" do
    test "saves content while the exam is running" do
      exam = exam_fixture(status: "running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())

      doc = sample_doc("Meine Antwort")
      assert {:ok, updated} = Exams.update_exam_submission_content(submission, doc)
      assert updated.content == doc
    end

    test "rejects saves once the exam is finished" do
      exam = exam_fixture(status: "running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())
      {:ok, _exam} = Exams.update_exam_status(:system, exam, "finished")

      assert {:error, :exam_not_running} =
               Exams.update_exam_submission_content(submission, sample_doc("zu spät"))
    end

    test "rejects saves after the submission was submitted" do
      exam = exam_fixture(status: "running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())
      {:ok, submitted} = Exams.submit_exam_submission(submission)

      assert {:error, :already_submitted} =
               Exams.update_exam_submission_content(submitted, sample_doc("nachträglich"))
    end
  end

  describe "submit_exam_submission/1" do
    test "marks the submission as submitted while running" do
      exam = exam_fixture(status: "running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())

      assert {:ok, submitted} = Exams.submit_exam_submission(submission)
      assert submitted.submitted
    end

    test "stamps submitted_at in the same write that flips the flag" do
      # `updated_at` is not the hand-in time: autosave moves it, and
      # auto-correction during a running exam can move it past the hand-in.
      exam = exam_fixture(status: "running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())
      refute submission.submitted_at

      before = DateTime.utc_now() |> DateTime.add(-1, :second)
      {:ok, submitted} = Exams.submit_exam_submission(submission)

      assert submitted.submitted_at
      assert DateTime.compare(submitted.submitted_at, before) == :gt
      assert DateTime.compare(submitted.submitted_at, DateTime.utc_now()) in [:lt, :eq]
    end

    test "rejects submission once the exam is finished" do
      exam = exam_fixture(status: "running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())
      {:ok, _exam} = Exams.update_exam_status(:system, exam, "finished")

      assert {:error, :exam_not_running} = Exams.submit_exam_submission(submission)
    end
  end

  describe "authorization" do
    import Tasky.AccountsFixtures

    test "a foreign teacher cannot mutate an exam they don't own" do
      exam = exam_fixture()
      other = user_scope_fixture(user_fixture(%{role: "teacher"}))

      assert {:error, :unauthorized} = Exams.update_exam(other, exam, %{name: "Übernommen"})
      assert {:error, :unauthorized} = Exams.delete_exam(other, exam)
      assert {:error, :unauthorized} = Exams.open_exam_session(other, exam, "anonymous")
      assert {:error, :unauthorized} = Exams.save_exam_structure(other, exam, %{"type" => "doc"})
      assert {:error, :unauthorized} = Exams.update_grading_max_points(other, exam, 10.0)
      assert {:error, :unauthorized} = Exams.assign_student(other, exam, 1)
      assert {:error, :unauthorized} = Exams.assign_students_from_class(other, exam, 1)
      assert {:error, :unauthorized} = Exams.return_exam(other, exam, %{})
      assert {:error, :unauthorized} = Exams.withdraw_exam_return(other, exam)
    end

    test "a foreign teacher cannot grade another teacher's submission" do
      exam = exam_fixture(status: "running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())
      other = user_scope_fixture(user_fixture(%{role: "teacher"}))

      assert {:error, :unauthorized} = Exams.set_part_points(other, submission, "q-1", 1.0)
      assert {:error, :unauthorized} = Exams.mark_part_corrected(other, submission, "q-1")
      assert {:error, :unauthorized} = Exams.set_submission_mark(other, submission, 5.0)
    end

    test "an admin can manage any teacher's exam" do
      exam = exam_fixture()
      admin = user_scope_fixture(user_fixture(%{role: "admin"}))

      assert {:ok, updated} = Exams.update_exam(admin, exam, %{name: "Admin-Bearbeitung"})
      assert updated.name == "Admin-Bearbeitung"
    end
  end

  describe "update_exam_status/3 lifecycle" do
    test "rejects transitions outside the lifecycle" do
      exam = exam_fixture()

      assert {:error, :invalid_transition} =
               Exams.update_exam_status(:system, exam, "finished")

      assert {:error, :invalid_transition} = Exams.update_exam_status(:system, exam, "draft")
    end

    test "a finished exam can be reopened, but not rewound further" do
      # "Prüfung beenden" is one click and used to be terminal: after it nobody
      # could save or hand in any more, with no way back.
      exam = exam_fixture(status: "running")
      {:ok, exam} = Exams.update_exam_status(:system, exam, "finished")

      assert {:ok, reopened} = Exams.update_exam_status(:system, exam, "running")
      assert reopened.status == "running"

      {:ok, finished} = Exams.update_exam_status(:system, reopened, "finished")
      assert {:error, :invalid_transition} = Exams.update_exam_status(:system, finished, "draft")
      assert {:error, :invalid_transition} = Exams.update_exam_status(:system, finished, "open")
    end

    test "reopening lets a participant write again" do
      exam = exam_fixture(status: "running")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())
      {:ok, exam} = Exams.update_exam_status(:system, exam, "finished")

      assert {:error, :exam_not_running} =
               Exams.update_exam_submission_content(submission, sample_doc("zu spät"))

      {:ok, _exam} = Exams.update_exam_status(:system, exam, "running")

      assert {:ok, updated} =
               Exams.update_exam_submission_content(submission, sample_doc("wieder offen"))

      assert updated.content == sample_doc("wieder offen")
    end

    test "status and enrollment_token are not mass-assignable" do
      exam = exam_fixture()

      {:ok, updated} =
        Exams.update_exam(:system, exam, %{
          "status" => "running",
          "enrollment_token" => "HACKED"
        })

      assert updated.status == "draft"
      assert updated.enrollment_token == nil
    end
  end

  describe "ExamUploadField.changeset/2" do
    alias Tasky.Exams.ExamUploadField

    test "rejects an untouched empty allowed_types default" do
      changeset = ExamUploadField.changeset(%ExamUploadField{}, %{label: "Datei"})

      refute changeset.valid?
      assert %{allowed_types: ["mindestens einen Dateityp wählen"]} = errors_on(changeset)
    end

    test "accepts a valid type selection" do
      changeset =
        ExamUploadField.changeset(%ExamUploadField{}, %{label: "Datei", allowed_types: ["pdf"]})

      assert changeset.valid?
    end
  end

  describe "duplicate guest enrollment" do
    test "the same email cannot enroll twice into one exam" do
      exam = exam_fixture(status: "open")

      assert {:ok, _} = Exams.create_exam_submission(exam, enrollment_attrs())
      assert {:error, changeset} = Exams.create_exam_submission(exam, enrollment_attrs())
      assert %{exam_id: [_message]} = errors_on(changeset)
    end
  end

  describe "update_grading_max_points/3 and set_submission_mark/2" do
    test "rejects a max that would corrupt every mark in the exam" do
      # `mark/2` divides by this. Negative clamps the whole class to 1.0, zero
      # removes every mark — and both are one typo away in the number field.
      exam = exam_fixture()

      assert {:error, :invalid_max_points} =
               Exams.update_grading_max_points(:system, exam, -6)

      assert {:error, :invalid_max_points} = Exams.update_grading_max_points(:system, exam, 0)
      assert {:error, :invalid_max_points} = Exams.update_grading_max_points(:system, exam, "20")

      assert Tasky.Repo.reload!(exam).grading_max_points == nil
    end

    test "accepts a positive max, quarter-rounded, and nil to clear it" do
      exam = exam_fixture()

      assert {:ok, updated} = Exams.update_grading_max_points(:system, exam, 20.3)
      assert updated.grading_max_points == 20.25

      assert {:ok, cleared} = Exams.update_grading_max_points(:system, updated, nil)
      assert cleared.grading_max_points == nil
    end

    test "a mark is normalized into the Swiss 1..6 range" do
      exam = exam_fixture(status: "open")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())

      assert {:ok, high} = Exams.set_submission_mark(:system, submission, 9.0)
      assert high.mark == 6.0

      assert {:ok, low} = Exams.set_submission_mark(:system, high, -3)
      assert low.mark == 1.0

      assert {:ok, rounded} = Exams.set_submission_mark(:system, low, 4.3)
      assert rounded.mark == 4.25

      assert {:ok, cleared} = Exams.set_submission_mark(:system, rounded, nil)
      assert cleared.mark == nil
    end
  end

  describe "SEB passwords" do
    test "the quit password is long, dictation-safe and grouped" do
      # Its SHA-256 ships inside the plain `.seb` file every participant
      # downloads, so it has to survive being public-by-construction. The old
      # 6-digit password had 900 000 candidates.
      passwords = for _ <- 1..100, do: Exams.generate_quit_password()

      for password <- passwords do
        assert password =~ ~r/^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{3}$/
        # Uppercase-only, so `l` never appears; `I`/`O` are out of the alphabet.
        refute password =~ ~r/[O0I1]/
      end

      assert length(Enum.uniq(passwords)) == 100
    end

    test "the admin password is long and never grouped" do
      passwords = for _ <- 1..100, do: Exams.generate_admin_password()

      for password <- passwords do
        assert password =~ ~r/^[A-Z2-9]{26}$/
      end

      assert length(Enum.uniq(passwords)) == 100
    end
  end

  describe "participation modes" do
    test "an anonymous session mints an enrollment token" do
      exam = exam_fixture(participation_mode: "anonymous", status: "open")

      assert exam.participation_mode == "anonymous"
      assert exam.enrollment_token
      assert Exams.anonymous_mode?(exam)
      refute Exams.assigned_mode?(exam)
    end

    test "an assigned session never mints an enrollment token" do
      exam = exam_fixture(participation_mode: "assigned", status: "open")

      assert exam.participation_mode == "assigned"
      refute exam.enrollment_token
      assert Exams.assigned_mode?(exam)
    end

    test "participation_mode is not mass-assignable" do
      exam = exam_fixture(participation_mode: "anonymous", status: "open")

      {:ok, updated} = Exams.update_exam(:system, exam, %{"participation_mode" => "assigned"})

      assert updated.participation_mode == "anonymous"
    end

    test "an unknown mode is refused" do
      exam = exam_fixture()
      scope = teacher_scope(exam)

      assert_raise FunctionClauseError, fn ->
        Exams.open_exam_session(scope, exam, "irgendwas")
      end
    end

    test "self-enrolment is refused on an assigned exam" do
      exam = exam_fixture(participation_mode: "assigned", status: "running")

      assert {:error, :exam_not_open} =
               Exams.create_exam_submission(exam, enrollment_attrs())
    end

    test "an assigned exam is not reachable through an enrollment token" do
      anonymous = exam_fixture(participation_mode: "anonymous", status: "open")
      token = anonymous.enrollment_token

      # Same token value, but the exam now runs in assigned mode.
      {:ok, _} =
        anonymous
        |> Ecto.Changeset.change(%{participation_mode: "assigned"})
        |> Tasky.Repo.update()

      refute Exams.get_exam_by_enrollment_token(token)
    end
  end

  describe "assign_student/3" do
    import Tasky.AccountsFixtures

    test "creates the submission right away, copying name and email" do
      exam = exam_fixture(participation_mode: "assigned", status: "open")
      student = user_fixture(%{role: "student", firstname: "Lena", lastname: "Meier"})

      assert {:ok, submission} = Exams.assign_student(teacher_scope(exam), exam, student.id)
      assert submission.user_id == student.id
      assert submission.firstname == "Lena"
      assert submission.lastname == "Meier"
      assert submission.email == student.email
      assert submission.exam_token
      refute submission.submitted
    end

    test "refuses a second assignment of the same student" do
      exam = exam_fixture(participation_mode: "assigned", status: "open")
      student = user_fixture(%{role: "student"})
      scope = teacher_scope(exam)

      assert {:ok, _} = Exams.assign_student(scope, exam, student.id)
      assert {:error, %Ecto.Changeset{}} = Exams.assign_student(scope, exam, student.id)
    end

    test "refuses non-students" do
      exam = exam_fixture(participation_mode: "assigned", status: "open")
      admin = user_fixture(%{role: "admin"})

      assert {:error, :not_a_student} = Exams.assign_student(teacher_scope(exam), exam, admin.id)
    end

    test "refuses an anonymous-mode exam" do
      exam = exam_fixture(participation_mode: "anonymous", status: "open")
      student = user_fixture(%{role: "student"})

      assert {:error, :not_assigned_mode} =
               Exams.assign_student(teacher_scope(exam), exam, student.id)
    end

    test "refuses a draft exam" do
      exam = exam_fixture()
      student = user_fixture(%{role: "student"})

      # A draft has no mode yet, so the mode gate is what fires first.
      assert {:error, :not_assigned_mode} =
               Exams.assign_student(teacher_scope(exam), exam, student.id)
    end

    test "assignment during a running exam is allowed" do
      exam = exam_fixture(participation_mode: "assigned", status: "running")
      student = user_fixture(%{role: "student"})

      assert {:ok, _} = Exams.assign_student(teacher_scope(exam), exam, student.id)
    end
  end

  describe "assign_students_from_class/3 and list_assignable_students/2" do
    import Tasky.AccountsFixtures
    import Tasky.ClassesFixtures

    test "assigns the whole class and skips those already assigned" do
      exam = exam_fixture(participation_mode: "assigned", status: "open")
      scope = teacher_scope(exam)
      class = class_fixture()
      a = user_fixture(%{role: "student", class_id: class.id})
      b = user_fixture(%{role: "student", class_id: class.id})
      _elsewhere = user_fixture(%{role: "student"})

      assert Enum.sort(Enum.map(Exams.list_assignable_students(exam, class.id), & &1.id)) ==
               Enum.sort([a.id, b.id])

      assert {:ok, %{assigned: 2, skipped: 0}} =
               Exams.assign_students_from_class(scope, exam, class.id)

      assert Exams.list_assignable_students(exam, class.id) == []
      assert length(Exams.list_exam_submissions(exam)) == 2

      # Nothing left to assign — and no error either.
      assert {:ok, %{assigned: 0, skipped: 0}} =
               Exams.assign_students_from_class(scope, exam, class.id)
    end

    test "already-assigned students drop out of the candidate list" do
      exam = exam_fixture(participation_mode: "assigned", status: "open")
      student = user_fixture(%{role: "student"})

      assert student.id in Enum.map(Exams.list_assignable_students(exam), & &1.id)
      {:ok, _} = Exams.assign_student(teacher_scope(exam), exam, student.id)
      refute student.id in Enum.map(Exams.list_assignable_students(exam), & &1.id)
    end
  end

  describe "unassign_student/3" do
    import Tasky.AccountsFixtures

    test "removes the assignment" do
      exam = exam_fixture(participation_mode: "assigned", status: "open")
      student = user_fixture(%{role: "student"})
      scope = teacher_scope(exam)
      {:ok, submission} = Exams.assign_student(scope, exam, student.id)

      assert {:ok, _} = Exams.unassign_student(scope, exam, submission)
      assert Exams.list_exam_submissions(exam) == []
      assert student.id in Enum.map(Exams.list_assignable_students(exam), & &1.id)
    end

    test "refuses once the participant has submitted" do
      exam = exam_fixture(participation_mode: "assigned", status: "running")
      student = user_fixture(%{role: "student"})
      scope = teacher_scope(exam)
      {:ok, submission} = Exams.assign_student(scope, exam, student.id)
      {:ok, submission} = Exams.submit_exam_submission(submission)

      assert {:error, :already_submitted} = Exams.unassign_student(scope, exam, submission)
    end

    test "refuses an anonymous submission" do
      exam = exam_fixture(participation_mode: "anonymous", status: "open")
      {:ok, submission} = Exams.create_exam_submission(exam, enrollment_attrs())

      assert {:error, :not_assigned} =
               Exams.unassign_student(teacher_scope(exam), exam, submission)
    end
  end

  describe "list_assigned_exams/1 and get_submission_for_user/2" do
    import Tasky.AccountsFixtures

    test "a student sees only their own assignments" do
      exam = exam_fixture(participation_mode: "assigned", status: "open")
      mine = user_fixture(%{role: "student"})
      theirs = user_fixture(%{role: "student"})
      scope = teacher_scope(exam)
      {:ok, own} = Exams.assign_student(scope, exam, mine.id)
      {:ok, _other} = Exams.assign_student(scope, exam, theirs.id)

      assert [listed] = Exams.list_assigned_exams(user_scope_fixture(mine))
      assert listed.id == own.id
      assert listed.exam.id == exam.id
      assert listed.exam.teacher

      assert Exams.get_submission_for_user(exam.id, mine.id).id == own.id
      refute Exams.get_submission_for_user(exam.id, user_fixture(%{role: "student"}).id)
    end

    test "anonymous exams never show up" do
      exam = exam_fixture(participation_mode: "anonymous", status: "open")
      {:ok, _} = Exams.create_exam_submission(exam, enrollment_attrs())
      student = user_fixture(%{role: "student"})

      assert Exams.list_assigned_exams(user_scope_fixture(student)) == []
    end

    test "teachers get nothing" do
      teacher = user_fixture(%{role: "teacher"})
      assert Exams.list_assigned_exams(user_scope_fixture(teacher)) == []
    end
  end

  describe "return_exam/3 and withdraw_exam_return/2" do
    test "stores the flags and can be withdrawn" do
      exam = exam_fixture(participation_mode: "assigned", status: "finished")
      scope = teacher_scope(exam)

      refute Exams.returned?(exam)

      assert {:ok, returned} =
               Exams.return_exam(scope, exam, %{
                 show_points_and_mark: true,
                 show_content: true,
                 show_correction: true,
                 show_sample_solution: false
               })

      assert Exams.returned?(returned)
      assert returned.returned_at
      assert returned.return_show_points_and_mark
      assert returned.return_show_content
      assert returned.return_show_correction
      refute returned.return_show_sample_solution

      assert {:ok, withdrawn} = Exams.withdraw_exam_return(scope, returned)
      refute Exams.returned?(withdrawn)
      # The flags survive, so they pre-fill the modal on a re-return.
      assert withdrawn.return_show_correction
    end

    test "refuses an unfinished exam" do
      exam = exam_fixture(participation_mode: "assigned", status: "running")

      assert {:error, :exam_not_finished} = Exams.return_exam(teacher_scope(exam), exam, %{})
    end

    test "refuses an anonymous exam" do
      exam = exam_fixture(participation_mode: "anonymous", status: "finished")

      assert {:error, :not_assigned_mode} = Exams.return_exam(teacher_scope(exam), exam, %{})
    end
  end
end
