defmodule Tasky.ExamsPhasesTest do
  use Tasky.DataCase, async: true

  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams
  alias Tasky.Exams.Exam
  alias Tasky.Repo

  setup do
    scope = user_scope_fixture(user_fixture(%{role: "teacher"}))
    %{scope: scope}
  end

  defp question(part_id, text) do
    attrs = if part_id, do: %{"level" => 3, "partId" => part_id}, else: %{"level" => 3}

    %{
      "type" => "heading",
      "attrs" => attrs,
      "content" => [%{"type" => "text", "text" => text}]
    }
  end

  defp doc(nodes), do: %{"type" => "doc", "content" => nodes}

  defp two_part_exam(scope, opts \\ []) do
    exam_fixture(
      Keyword.merge(
        [scope: scope, attrs: %{content: doc([question("p1", "Eins"), question("p2", "Zwei")])}],
        opts
      )
    )
  end

  defp finish(scope, exam) do
    {:ok, exam} = Exams.update_exam_status(scope, exam, "running")
    {:ok, exam} = Exams.update_exam_status(scope, exam, "finished")
    exam
  end

  defp corrected(submission, parts) do
    submission |> Ecto.Changeset.change(corrected_parts: parts) |> Repo.update!()
  end

  defp returned(exam) do
    exam |> Exam.return_changeset(%{returned_at: DateTime.utc_now(:second)}) |> Repo.update!()
  end

  defp phase(scope, exam) do
    exam = Repo.reload!(exam)
    Map.fetch!(Exams.exam_phases(scope, [exam]), exam.id)
  end

  describe "part_ids" do
    test "follow the content on every save", %{scope: scope} do
      exam = two_part_exam(scope)
      assert exam.part_ids == ["p1", "p2"]

      {:ok, exam} =
        exam
        |> Exam.document_changeset(%{content: doc([question("p3", "Drei")])})
        |> Repo.update()

      assert exam.part_ids == ["p3"]
    end

    test "follow the editor's save", %{scope: scope} do
      exam = two_part_exam(scope)

      {:ok, exam} =
        Exams.save_exam_structure(
          scope,
          exam,
          doc([question("p2", "Zwei"), question("p4", "Vier")])
        )

      assert exam.part_ids == ["p2", "p4"]
    end

    test "a free-document exam has its one part", %{scope: scope} do
      exam = exam_fixture(scope: scope, answer_mode: "free_document")
      assert exam.part_ids == [Tasky.ExamDoc.free_document_part_id()]
    end

    test "headings without a partId get the positional ids", %{scope: scope} do
      content = doc([question(nil, "Eins"), question(nil, "Zwei")])
      exam = exam_fixture(scope: scope, attrs: %{content: content})

      expected =
        content |> Exams.split_content_into_parts("answer_fields") |> Enum.map(& &1.id)

      assert exam.part_ids == expected
      assert expected != []
    end

    test "a duplicate carries them", %{scope: scope} do
      exam = two_part_exam(scope)
      {:ok, copy} = Exams.duplicate_exam(scope, exam, "Kopie")

      assert copy.part_ids == ["p1", "p2"]
    end
  end

  describe "exam_phases/2" do
    test "an exam before its end has its status as phase", %{scope: scope} do
      for status <- ~w(draft open running) do
        assert phase(scope, two_part_exam(scope, status: status)) == status
      end
    end

    test "a finished exam with an uncorrected part is being corrected", %{scope: scope} do
      exam = two_part_exam(scope, status: "open")
      exam |> exam_submission_fixture() |> corrected(["p1", "p2"])
      exam |> exam_submission_fixture(%{"email" => "b@example.com"}) |> corrected(["p1"])

      assert phase(scope, finish(scope, exam)) == "correcting"
    end

    test "a finished exam with every part corrected is ready to return", %{scope: scope} do
      exam = two_part_exam(scope, status: "open")
      exam |> exam_submission_fixture() |> corrected(["p2", "p1"])

      assert phase(scope, finish(scope, exam)) == "ready_to_return"
    end

    test "a part deleted after its correction does not count", %{scope: scope} do
      exam = two_part_exam(scope, status: "open")
      exam |> exam_submission_fixture() |> corrected(["p1", "p2", "gone"])

      assert phase(scope, finish(scope, exam)) == "ready_to_return"
    end

    test "a finished exam nobody sat is ready to return", %{scope: scope} do
      assert phase(scope, two_part_exam(scope, status: "finished")) == "ready_to_return"
    end

    test "a returned exam is returned, corrected or not", %{scope: scope} do
      exam = two_part_exam(scope, status: "open")
      exam_submission_fixture(exam)

      assert phase(scope, returned(finish(scope, exam))) == "returned"
    end

    test "leaves out exams the scope cannot manage", %{scope: scope} do
      other = user_scope_fixture(user_fixture(%{role: "teacher"}))
      exam = two_part_exam(scope)

      assert Exams.exam_phases(other, [exam]) == %{}
    end
  end
end
