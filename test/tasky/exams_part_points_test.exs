defmodule Tasky.ExamsPartPointsTest do
  use Tasky.DataCase, async: true

  import Tasky.AccountsFixtures

  alias Tasky.Exams

  defp content do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3, "partId" => "q-1"},
          "content" => [%{"type" => "text", "text" => "Frage Eins"}]
        },
        %{"type" => "answerBlock", "attrs" => %{"answerId" => "a1"}},
        %{"type" => "answerBlock", "attrs" => %{"answerId" => "a2"}}
      ]
    }
  end

  defp create_exam(attrs \\ %{}) do
    scope = user_scope_fixture(user_fixture(%{role: "teacher"}))

    {:ok, exam} =
      Tasky.ExamsFixtures.create_exam_with_document(
        scope,
        Map.merge(
          %{
            name: "Test Prüfung",
            content: content(),
            sample_solution_points: %{"q-1" => 4},
            sample_solution_block_points: %{"q-1" => %{"a1" => 3, "a2" => 1}}
          },
          attrs
        )
      )

    %{scope: scope, exam: exam}
  end

  describe "learner_visible_part_points/1" do
    test "shows each question's total by default" do
      %{exam: exam} = create_exam()

      assert exam.show_part_points
      assert Exams.learner_visible_part_points(exam) == %{"q-1" => 4}
    end

    test "never hands out the split over the answer fields" do
      %{exam: exam} = create_exam()

      refute inspect(Exams.learner_visible_part_points(exam)) =~ "a1"
    end

    test "is nil when the teacher hides the points" do
      %{scope: scope, exam: exam} = create_exam()
      {:ok, exam} = Exams.set_show_part_points(scope, exam, false)

      assert Exams.learner_visible_part_points(exam) == nil
    end

    test "is nil for a free document" do
      %{exam: exam} = create_exam()

      assert Exams.learner_visible_part_points(%{exam | answer_mode: "free_document"}) == nil
    end
  end

  describe "set_show_part_points/3" do
    test "takes the checkbox value" do
      %{scope: scope, exam: exam} = create_exam()

      {:ok, exam} = Exams.set_show_part_points(scope, exam, "false")
      refute exam.show_part_points

      {:ok, exam} = Exams.set_show_part_points(scope, exam, "true")
      assert exam.show_part_points
    end

    test "another teacher cannot change it" do
      %{exam: exam} = create_exam()
      other = user_scope_fixture(user_fixture(%{role: "teacher"}))

      assert {:error, _} = Exams.set_show_part_points(other, exam, false)
    end
  end

  describe "duplicate_exam/3" do
    test "carries the setting over" do
      %{scope: scope, exam: exam} = create_exam()
      {:ok, exam} = Exams.set_show_part_points(scope, exam, false)

      {:ok, copy} = Exams.duplicate_exam(scope, exam, "Kopie")

      refute copy.show_part_points
    end
  end
end
