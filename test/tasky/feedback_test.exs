defmodule Tasky.FeedbackTest do
  use Tasky.DataCase, async: true

  import Tasky.AccountsFixtures
  import Tasky.CoursesFixtures
  import Tasky.FeedbackFixtures

  alias Tasky.Feedback
  alias Tasky.Feedback.Message

  setup do
    teacher_scope = user_scope_fixture(user_fixture(%{role: "teacher"}))
    course = course_fixture(scope: teacher_scope, attrs: %{feedback_box_enabled: true})

    student = user_fixture(%{role: "student"})
    enroll_fixture(course, student)

    %{
      teacher_scope: teacher_scope,
      course: course,
      student: student,
      student_scope: user_scope_fixture(student)
    }
  end

  describe "create_message/3" do
    test "an enrolled student can write", ctx do
      assert {:ok, message} =
               Feedback.create_message(ctx.student_scope, ctx.course.id, %{
                 "body" => "Kapitel 3 war zu schnell."
               })

      assert message.body == "Kapitel 3 war zu schnell."
      assert message.course_id == ctx.course.id
      refute message.read_at
    end

    test "a student who is not enrolled gets nothing", ctx do
      outsider = user_scope_fixture(user_fixture(%{role: "student"}))

      assert {:error, :not_found} =
               Feedback.create_message(outsider, ctx.course.id, %{"body" => "Hallo"})
    end

    test "a closed mailbox refuses the message", ctx do
      closed = course_fixture(scope: ctx.teacher_scope)
      enroll_fixture(closed, ctx.student)

      assert {:error, :disabled} =
               Feedback.create_message(ctx.student_scope, closed.id, %{"body" => "Hallo"})
    end

    test "a teacher cannot write into a mailbox", ctx do
      assert {:error, :not_found} =
               Feedback.create_message(ctx.teacher_scope, ctx.course.id, %{"body" => "Hallo"})
    end

    test "an empty or whitespace-only message is rejected", ctx do
      assert {:error, changeset} =
               Feedback.create_message(ctx.student_scope, ctx.course.id, %{"body" => "   \n "})

      assert %{body: ["Bitte schreibe zuerst etwas."]} = errors_on(changeset)
    end

    test "an over-long message is rejected", ctx do
      too_long = String.duplicate("a", Message.max_body_chars() + 1)

      assert {:error, changeset} =
               Feedback.create_message(ctx.student_scope, ctx.course.id, %{"body" => too_long})

      assert %{body: [_]} = errors_on(changeset)
    end

    test "trims surrounding whitespace", ctx do
      {:ok, message} =
        Feedback.create_message(ctx.student_scope, ctx.course.id, %{"body" => "  Danke!  "})

      assert message.body == "Danke!"
    end

    test "the sixth message within the window is rate limited", ctx do
      for n <- 1..5 do
        assert {:ok, _} =
                 Feedback.create_message(ctx.student_scope, ctx.course.id, %{
                   "body" => "Nachricht #{n}"
                 })
      end

      assert {:error, :rate_limited} =
               Feedback.create_message(ctx.student_scope, ctx.course.id, %{"body" => "Nummer 6"})
    end

    test "the rate limit is per course", ctx do
      other = course_fixture(scope: ctx.teacher_scope, attrs: %{feedback_box_enabled: true})
      enroll_fixture(other, ctx.student)

      for n <- 1..5 do
        {:ok, _} =
          Feedback.create_message(ctx.student_scope, ctx.course.id, %{"body" => "Nachricht #{n}"})
      end

      assert {:ok, _} =
               Feedback.create_message(ctx.student_scope, other.id, %{"body" => "Anderer Kurs"})
    end
  end

  describe "list_messages/2" do
    test "never hands the sender to the caller", ctx do
      {:ok, written} =
        Feedback.create_message(ctx.student_scope, ctx.course.id, %{"body" => "Anonym?"})

      assert {:ok, [listed]} = Feedback.list_messages(ctx.teacher_scope, ctx.course)
      assert listed.body == "Anonym?"
      refute listed.student_id

      # ... obwohl die Zeile die Zuordnung sehr wohl trägt.
      assert Repo.get!(Message, written.id).student_id == ctx.student.id
    end

    test "returns the newest message first", ctx do
      older = feedback_message_fixture(ctx.course, ctx.student, %{body: "Zuerst"})

      Repo.update_all(
        from(m in Message, where: m.id == ^older.id),
        set: [inserted_at: ~U[2026-01-01 08:00:00Z]]
      )

      feedback_message_fixture(ctx.course, ctx.student, %{body: "Danach"})

      assert {:ok, [first, second]} = Feedback.list_messages(ctx.teacher_scope, ctx.course)
      assert first.body == "Danach"
      assert second.body == "Zuerst"
    end

    test "only returns messages of this course", ctx do
      other = course_fixture(scope: ctx.teacher_scope, attrs: %{feedback_box_enabled: true})
      feedback_message_fixture(ctx.course, ctx.student, %{body: "Meiner"})
      feedback_message_fixture(other, ctx.student, %{body: "Anderer"})

      assert {:ok, [message]} = Feedback.list_messages(ctx.teacher_scope, ctx.course)
      assert message.body == "Meiner"
    end

    test "refuses a course owned by someone else", ctx do
      stranger = user_scope_fixture(user_fixture(%{role: "teacher"}))

      assert {:error, :unauthorized} = Feedback.list_messages(stranger, ctx.course)
    end

    test "an admin may read any mailbox", ctx do
      feedback_message_fixture(ctx.course, ctx.student)
      admin = user_scope_fixture(user_fixture(%{role: "admin"}))

      assert {:ok, [_]} = Feedback.list_messages(admin, ctx.course)
    end
  end

  describe "mark_read/2, mark_unread/2 and toggle_read/2" do
    setup ctx do
      Map.put(ctx, :message, feedback_message_fixture(ctx.course, ctx.student))
    end

    test "mark_read sets read_at, mark_unread clears it", ctx do
      assert {:ok, read} = Feedback.mark_read(ctx.teacher_scope, ctx.message.id)
      assert read.read_at
      refute read.student_id

      assert {:ok, unread} = Feedback.mark_unread(ctx.teacher_scope, ctx.message.id)
      refute unread.read_at
    end

    test "toggle_read flips the current value", ctx do
      assert {:ok, read} = Feedback.toggle_read(ctx.teacher_scope, ctx.message.id)
      assert read.read_at

      assert {:ok, unread} = Feedback.toggle_read(ctx.teacher_scope, ctx.message.id)
      refute unread.read_at
    end

    test "a foreign teacher may not touch the message", ctx do
      stranger = user_scope_fixture(user_fixture(%{role: "teacher"}))

      assert {:error, :unauthorized} = Feedback.toggle_read(stranger, ctx.message.id)
      assert {:error, :unauthorized} = Feedback.mark_read(stranger, ctx.message.id)
      refute Repo.get!(Message, ctx.message.id).read_at
    end

    test "an unknown id is not found", ctx do
      assert {:error, :not_found} = Feedback.mark_read(ctx.teacher_scope, -1)
    end
  end

  describe "delete_message/2" do
    test "removes the row and returns it without the sender", ctx do
      message = feedback_message_fixture(ctx.course, ctx.student)

      assert {:ok, deleted} = Feedback.delete_message(ctx.teacher_scope, message.id)
      refute deleted.student_id
      refute Repo.get(Message, message.id)
    end

    test "a foreign teacher may not delete", ctx do
      message = feedback_message_fixture(ctx.course, ctx.student)
      stranger = user_scope_fixture(user_fixture(%{role: "teacher"}))

      assert {:error, :unauthorized} = Feedback.delete_message(stranger, message.id)
      assert Repo.get(Message, message.id)
    end
  end

  describe "cascades" do
    test "deleting the course removes its messages", ctx do
      message = feedback_message_fixture(ctx.course, ctx.student)

      {:ok, _} = Tasky.Courses.delete_course(ctx.course)

      refute Repo.get(Message, message.id)
    end
  end
end
