defmodule Tasky.TasksSolutionTest do
  @moduledoc """
  Musterlösung einer Lerneinheit und die Freigabe an Lernende.

  Die Wahrheitstabelle von `solution_visible?/2` ist der Kern: es ist das
  einzige Tor für Musterlösung *und* Korrektur, und jede Regressionsgefahr in
  diesem Feature läuft durch diese Funktion.
  """
  use Tasky.DataCase, async: true

  alias Tasky.Tasks
  alias Tasky.Tasks.TaskSubmission

  import Tasky.AccountsFixtures, only: [user_fixture: 1, user_scope_fixture: 1]
  import Tasky.CoursesFixtures
  import Tasky.TasksFixtures

  setup do
    teacher_scope = user_scope_fixture(user_fixture(%{role: "teacher"}))
    student = user_fixture(%{role: "student"})
    student_scope = user_scope_fixture(student)

    course = course_fixture(scope: teacher_scope)
    :ok = ensure_enrolled(course, student)

    task =
      task_fixture(teacher_scope, %{status: "published", course_id: course.id})

    %{
      teacher_scope: teacher_scope,
      student: student,
      student_scope: student_scope,
      course: course,
      task: task
    }
  end

  defp ensure_enrolled(course, student) do
    {:ok, _} = Tasky.Courses.enroll_student(course.id, student.id)
    :ok
  end

  defp submission(student_scope, task) do
    {:ok, submission} = Tasks.get_or_create_submission(student_scope, task.id)
    submission
  end

  # Ein Dokument mit zwei Antwortfeldern und stabilen ids.
  defp doc_with_answers(ids, filled \\ %{}) do
    %{
      "type" => "doc",
      "content" =>
        Enum.map(ids, fn id ->
          %{
            "type" => "answerBlock",
            "attrs" => %{"answerId" => id},
            "content" => Map.get(filled, id, [%{"type" => "paragraph"}])
          }
        end)
    }
  end

  defp text_node(text) do
    [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}]
  end

  describe "save_sample_solution/3" do
    test "speichert nur die Antworten, nicht den Inhalt", %{teacher_scope: scope, task: task} do
      {:ok, task} = Tasks.save_task_content(scope, task, doc_with_answers(["a1", "a2"]))

      filled = doc_with_answers(["a1", "a2"], %{"a1" => text_node("Lösung A")})
      assert {:ok, task} = Tasks.save_sample_solution(scope, task, filled)

      assert Map.keys(task.sample_solution) |> Enum.sort() == ["a1", "a2"]
      assert task.sample_solution["a1"] == text_node("Lösung A")

      # Der Inhalt bleibt antwortfrei — der Musterlösungs-Tab fasst ihn nicht an.
      assert %{"content" => [block_a, _block_b]} = task.content
      assert block_a["content"] == [%{"type" => "paragraph"}]
    end

    test "rekonstruiert das antwortgefüllte Dokument", %{teacher_scope: scope, task: task} do
      {:ok, task} = Tasks.save_task_content(scope, task, doc_with_answers(["a1"]))
      filled = doc_with_answers(["a1"], %{"a1" => text_node("Lösung A")})
      {:ok, task} = Tasks.save_sample_solution(scope, task, filled)

      assert %{"content" => [%{"content" => content}]} = Tasks.sample_solution_doc(task)
      assert content == text_node("Lösung A")
    end

    test "ersetzt statt zu mergen — gelöschte Antworten kommen nicht zurück", %{
      teacher_scope: scope,
      task: task
    } do
      {:ok, task} = Tasks.save_task_content(scope, task, doc_with_answers(["a1", "a2"]))

      {:ok, task} =
        Tasks.save_sample_solution(
          scope,
          task,
          doc_with_answers(["a1", "a2"], %{
            "a1" => text_node("A"),
            "a2" => text_node("B")
          })
        )

      {:ok, task} =
        Tasks.save_sample_solution(
          scope,
          task,
          doc_with_answers(["a1", "a2"], %{"a1" => text_node("A")})
        )

      assert task.sample_solution["a1"] == text_node("A")
      # a2 ist geleert, nicht wiederauferstanden
      assert task.sample_solution["a2"] == [%{"type" => "paragraph"}]
    end

    test "verwirft Antworten zu ids, die es im Inhalt nicht gibt", %{
      teacher_scope: scope,
      task: task
    } do
      {:ok, task} = Tasks.save_task_content(scope, task, doc_with_answers(["a1"]))

      filled =
        doc_with_answers(["a1", "fremd"], %{
          "a1" => text_node("A"),
          "fremd" => text_node("Waise")
        })

      assert {:ok, task} = Tasks.save_sample_solution(scope, task, filled)
      assert Map.keys(task.sample_solution) == ["a1"]
    end

    test "prunt Waisen, wenn der Inhalt ein Antwortfeld verliert", %{
      teacher_scope: scope,
      task: task
    } do
      {:ok, task} = Tasks.save_task_content(scope, task, doc_with_answers(["a1", "a2"]))

      {:ok, task} =
        Tasks.save_sample_solution(
          scope,
          task,
          doc_with_answers(["a1", "a2"], %{"a1" => text_node("A"), "a2" => text_node("B")})
        )

      assert {:ok, task} = Tasks.save_task_content(scope, task, doc_with_answers(["a1"]))
      assert Map.keys(task.sample_solution) == ["a1"]
    end

    test "weist eine fremde Lehrperson ab", %{task: task} do
      other = user_scope_fixture(user_fixture(%{role: "teacher"}))

      assert {:error, :unauthorized} =
               Tasks.save_sample_solution(other, task, doc_with_answers(["a1"]))
    end

    test "lehnt eine zu grosse Musterlösung ab", %{teacher_scope: scope, task: task} do
      {:ok, task} = Tasks.save_task_content(scope, task, doc_with_answers(["a1"]))
      huge = doc_with_answers(["a1"], %{"a1" => text_node(String.duplicate("x", 6_000_000))})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Tasks.save_sample_solution(scope, task, huge)

      assert "Musterlösung ist zu gross" in errors_on(changeset).sample_solution
    end
  end

  describe "answer_block_count/1" do
    test "zählt die Antwortfelder des Inhalts", %{teacher_scope: scope, task: task} do
      assert Tasks.answer_block_count(task) == 0

      {:ok, task} = Tasks.save_task_content(scope, task, doc_with_answers(["a1", "a2"]))
      assert Tasks.answer_block_count(task) == 2
    end
  end

  describe "Freigabe-Modus über update_task/3" do
    test "setzt einen gültigen Modus", %{teacher_scope: scope, task: task} do
      assert task.solution_release_mode == "never"
      assert {:ok, task} = Tasks.update_task(scope, task, %{solution_release_mode: "on_complete"})
      assert task.solution_release_mode == "on_complete"
    end

    test "weist einen unbekannten Modus ab", %{teacher_scope: scope, task: task} do
      assert {:error, changeset} =
               Tasks.update_task(scope, task, %{solution_release_mode: "vielleicht"})

      assert errors_on(changeset).solution_release_mode != []
    end

    test "weist eine fremde Lehrperson ab", %{task: task} do
      other = user_scope_fixture(user_fixture(%{role: "teacher"}))

      assert {:error, :unauthorized} =
               Tasks.update_task(other, task, %{solution_release_mode: "manual"})
    end
  end

  describe "solution_visible?/2 — die Wahrheitstabelle" do
    @modes ~w(never manual on_complete)
    @open_statuses ~w(not_started in_progress in_revision review_denied)
    @done_statuses ~w(completed review_approved)

    test "nil-Abgabe sieht nie etwas" do
      for mode <- @modes do
        refute Tasks.solution_visible?(%Tasky.Tasks.Task{solution_release_mode: mode}, nil)
      end
    end

    test "ohne Freigabe und ohne Abschluss bleibt alles zu" do
      for mode <- @modes, status <- @open_statuses do
        task = %Tasky.Tasks.Task{solution_release_mode: mode}
        submission = %TaskSubmission{status: status, completed_at: nil}
        refute Tasks.solution_visible?(task, submission)
      end
    end

    test "manuelle Freigabe öffnet in jedem Modus ausser never" do
      released = %TaskSubmission{solution_released_at: DateTime.utc_now(:second)}

      refute Tasks.solution_visible?(
               %Tasky.Tasks.Task{solution_release_mode: "never"},
               released
             )

      for mode <- ~w(manual on_complete) do
        assert Tasks.solution_visible?(%Tasky.Tasks.Task{solution_release_mode: mode}, released)
      end
    end

    test "on_complete öffnet mit completed_at, manual nicht" do
      for status <- @done_statuses do
        submission = %TaskSubmission{status: status, completed_at: DateTime.utc_now(:second)}

        assert Tasks.solution_visible?(
                 %Tasky.Tasks.Task{solution_release_mode: "on_complete"},
                 submission
               )

        refute Tasks.solution_visible?(
                 %Tasky.Tasks.Task{solution_release_mode: "manual"},
                 submission
               )
      end
    end

    test "never überstimmt eine bereits erteilte Freigabe" do
      submission = %TaskSubmission{
        solution_released_at: DateTime.utc_now(:second),
        completed_at: DateTime.utc_now(:second)
      }

      refute Tasks.solution_visible?(
               %Tasky.Tasks.Task{solution_release_mode: "never"},
               submission
             )
    end
  end

  describe "release_solution/3" do
    setup %{teacher_scope: scope, task: task} do
      {:ok, task} = Tasks.update_task(scope, task, %{solution_release_mode: "manual"})
      %{task: task}
    end

    test "stempelt die Freigabe", %{teacher_scope: scope, task: task, student_scope: student} do
      submission = submission(student, task)
      refute submission.solution_released_at

      assert {:ok, released} = Tasks.release_solution(scope, task, submission.id)
      assert %DateTime{} = released.solution_released_at
      assert Tasks.solution_visible?(task, released)
    end

    test "ist idempotent und behält den ersten Zeitstempel", %{
      teacher_scope: scope,
      task: task,
      student_scope: student
    } do
      submission = submission(student, task)
      {:ok, first} = Tasks.release_solution(scope, task, submission.id)
      {:ok, second} = Tasks.release_solution(scope, task, submission.id)

      assert second.solution_released_at == first.solution_released_at
    end

    test "sendet auf beide PubSub-Topics", %{
      teacher_scope: scope,
      task: task,
      student: student,
      student_scope: student_scope,
      course: course
    } do
      submission = submission(student_scope, task)

      Phoenix.PubSub.subscribe(Tasky.PubSub, "student:#{student.id}:submissions")
      Phoenix.PubSub.subscribe(Tasky.PubSub, "course:#{course.id}:progress")

      {:ok, _} = Tasks.release_solution(scope, task, submission.id)

      assert_receive {:submission_updated, _}
      assert_receive {:submission_updated, _}
    end

    test "lehnt eine Abgabe einer anderen Lerneinheit ab", %{
      teacher_scope: scope,
      task: task,
      student_scope: student_scope,
      course: course
    } do
      other_task =
        task_fixture(scope, %{status: "published", course_id: course.id, position: 99})

      foreign = submission(student_scope, other_task)

      assert {:error, :not_found} = Tasks.release_solution(scope, task, foreign.id)
    end

    test "weist eine fremde Lehrperson ab", %{task: task, student_scope: student_scope} do
      submission = submission(student_scope, task)
      other = user_scope_fixture(user_fixture(%{role: "teacher"}))

      assert {:error, :unauthorized} = Tasks.release_solution(other, task, submission.id)
    end
  end

  describe "release_solution_bulk/3" do
    setup %{teacher_scope: scope, task: task, course: course} do
      {:ok, task} = Tasks.update_task(scope, task, %{solution_release_mode: "manual"})

      others =
        for _ <- 1..2 do
          student = user_fixture(%{role: "student"})
          :ok = ensure_enrolled(course, student)
          {:ok, submission} = Tasks.get_or_create_submission(user_scope_fixture(student), task.id)
          submission
        end

      %{task: task, others: others}
    end

    test "gibt für alle frei", %{
      teacher_scope: scope,
      task: task,
      student_scope: student_scope,
      others: others
    } do
      mine = submission(student_scope, task)

      assert {:ok, updated} = Tasks.release_solution_bulk(scope, task, :all)
      assert length(updated) == length(others) + 1
      assert Enum.all?(updated, &match?(%DateTime{}, &1.solution_released_at))

      assert %DateTime{} = Repo.reload!(mine).solution_released_at
    end

    # Ohne das würde die Lehrperson für eine ganze Klasse freigeben, eine
    # Erfolgsmeldung sehen — und bei allen, die noch nie geöffnet haben, wäre
    # nichts passiert.
    test "erfasst auch Lernende, die die Einheit noch nie geöffnet haben", %{
      teacher_scope: scope,
      task: task,
      course: course
    } do
      neuling = user_fixture(%{role: "student"})
      :ok = ensure_enrolled(course, neuling)
      refute Tasks.get_submission_for_student(task.id, neuling.id)

      assert {:ok, updated} = Tasks.release_solution_bulk(scope, task, :all)

      submission = Tasks.get_submission_for_student(task.id, neuling.id)
      assert %DateTime{} = submission.solution_released_at
      assert submission.status == "not_started"
      assert submission.id in Enum.map(updated, & &1.id)
      assert Tasks.solution_visible?(task, submission)
    end

    test "gibt nur die genannten Abgaben frei", %{
      teacher_scope: scope,
      task: task,
      student_scope: student_scope,
      others: [first, second]
    } do
      mine = submission(student_scope, task)

      assert {:ok, updated} = Tasks.release_solution_bulk(scope, task, [first.id])
      assert length(updated) == 1

      assert %DateTime{} = Repo.reload!(first).solution_released_at
      refute Repo.reload!(second).solution_released_at
      refute Repo.reload!(mine).solution_released_at
    end

    test "ist idempotent", %{teacher_scope: scope, task: task, student_scope: student_scope} do
      mine = submission(student_scope, task)
      {:ok, _} = Tasks.release_solution_bulk(scope, task, :all)
      first = Repo.reload!(mine).solution_released_at

      {:ok, _} = Tasks.release_solution_bulk(scope, task, :all)
      assert Repo.reload!(mine).solution_released_at == first
    end

    test "ignoriert Abgaben einer anderen Lerneinheit", %{
      teacher_scope: scope,
      task: task,
      course: course,
      student_scope: student_scope
    } do
      other_task = task_fixture(scope, %{status: "published", course_id: course.id, position: 99})
      foreign = submission(student_scope, other_task)

      assert {:ok, []} = Tasks.release_solution_bulk(scope, task, [foreign.id])
      refute Repo.reload!(foreign).solution_released_at
    end

    test "sendet pro Abgabe auf beide Topics", %{
      teacher_scope: scope,
      task: task,
      student: student,
      student_scope: student_scope,
      course: course
    } do
      _mine = submission(student_scope, task)

      Phoenix.PubSub.subscribe(Tasky.PubSub, "student:#{student.id}:submissions")
      Phoenix.PubSub.subscribe(Tasky.PubSub, "course:#{course.id}:progress")

      {:ok, updated} = Tasks.release_solution_bulk(scope, task, :all)

      # Ein Broadcast pro Abgabe auf dem Kurs-Topic, plus einer auf dem
      # eigenen Topic der/des Lernenden.
      for _ <- 1..(length(updated) + 1), do: assert_receive({:submission_updated, _})
    end

    test "weist eine fremde Lehrperson ab", %{task: task} do
      other = user_scope_fixture(user_fixture(%{role: "teacher"}))
      assert {:error, :unauthorized} = Tasks.release_solution_bulk(other, task, :all)
    end
  end

  describe "Freigabe bleibt bestehen" do
    test "überlebt Rückgabe und erneutes Einreichen", %{
      teacher_scope: scope,
      task: task,
      student_scope: student_scope
    } do
      {:ok, task} = Tasks.update_task(scope, task, %{solution_release_mode: "manual"})
      submission = submission(student_scope, task)

      {:ok, _} = Tasks.complete_task(student_scope, submission.id)
      {:ok, released} = Tasks.release_solution(scope, task, submission.id)
      stamp = released.solution_released_at

      {:ok, denied} = Tasks.review_submission(scope, submission.id, "review_denied", %{})
      assert denied.solution_released_at == stamp
      assert Tasks.solution_visible?(task, denied)

      {:ok, again} = Tasks.complete_task(student_scope, submission.id)
      assert again.solution_released_at == stamp
      assert Tasks.solution_visible?(task, again)
    end

    test "on_complete bleibt über eine Rückgabe hinweg offen", %{
      teacher_scope: scope,
      task: task,
      student_scope: student_scope
    } do
      {:ok, task} = Tasks.update_task(scope, task, %{solution_release_mode: "on_complete"})
      submission = submission(student_scope, task)

      {:ok, completed} = Tasks.complete_task(student_scope, submission.id)
      assert Tasks.solution_visible?(task, completed)

      {:ok, denied} = Tasks.review_submission(scope, submission.id, "review_denied", %{})
      assert denied.status == "review_denied"
      # completed_at wird nie geräumt — genau darauf ruht die Klebrigkeit.
      assert Tasks.solution_visible?(task, denied)
    end
  end
end
