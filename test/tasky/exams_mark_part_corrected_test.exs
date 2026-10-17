defmodule Tasky.ExamsMarkPartCorrectedTest do
  @moduledoc """
  Marking a part done in the single correction stores the pre-judged verdicts
  of untouched blocks, so the read-only total is not lost — unless a total was
  already stored.
  """
  use Tasky.DataCase, async: true

  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  @content %{
    "type" => "doc",
    "content" => [
      %{
        "type" => "heading",
        "attrs" => %{"level" => 3, "partId" => "q-1"},
        "content" => [%{"type" => "text", "text" => "Übersetzung"}]
      },
      %{
        "type" => "answerBlock",
        "attrs" => %{"answerId" => "a1"},
        "content" => [%{"type" => "paragraph"}]
      }
    ]
  }

  setup do
    scope = user_scope_fixture(user_fixture(%{role: "teacher"}))

    exam =
      exam_fixture(
        scope: scope,
        status: "running",
        attrs: %{content: @content, sample_solution_points: %{"q-1" => 2}}
      )

    {:ok, submission} =
      exam |> exam_submission_fixture() |> Exams.update_exam_submission_content(@content)

    %{scope: scope, submission: submission}
  end

  test "stores the defaults of untouched blocks with the flag", ctx do
    {:ok, updated} =
      Exams.mark_part_corrected(ctx.scope, ctx.submission, "q-1", %{0 => "correct"})

    assert "q-1" in updated.corrected_parts
    assert updated.points_per_part["q-1"] == 2
  end

  test "keeps an explicit verdict over the default", ctx do
    {:ok, judged} = Exams.set_block_verdict(ctx.scope, ctx.submission, "q-1", 0, "wrong")

    {:ok, updated} = Exams.mark_part_corrected(ctx.scope, judged, "q-1", %{0 => "correct"})

    assert updated.points_per_part["q-1"] == 0
  end

  test "leaves a total typed by hand alone", ctx do
    {:ok, typed} = Exams.set_part_points(ctx.scope, ctx.submission, "q-1", 0.5)

    {:ok, updated} = Exams.mark_part_corrected(ctx.scope, typed, "q-1", %{0 => "correct"})

    assert "q-1" in updated.corrected_parts
    assert updated.points_per_part["q-1"] == 0.5
    assert updated.block_verdicts in [nil, %{}]
  end
end
