defmodule Tasky.Repo.Migrations.AddCorrectionConfigToTasks do
  @moduledoc """
  The correction options of a learning unit, per question, as exams have them
  (`Tasky.Correction.PartConfig`): `tasks.correction_config` maps a question's
  `partId` to its options.

  Until now a unit had one fixed rule (ignore case, nothing else) and a list of
  answer fields left out of the self-check (`self_check_off`). This converts
  each unit:

    * Answer fields only count when they stand under a question heading (h3),
      as in an exam. A unit with answer fields before its first question — or
      without any question — gets a heading "Aufgabe" right before the first
      top-level node holding one, so those fields keep being checked. The
      `answerId`s stay, so the sample solution and every submission still match.
    * Every heading gets a stable `partId` (`Tasky.ExamDoc.ensure_part_ids/1`).
    * A question is auto-corrected when at least one of its text fields was
      checked before, and ignores case as before. Questions of only ticks and
      pins are checked anyway.

  `self_check_off` stays for now and is dropped in a later deploy, once no
  running release reads it.
  """

  use Ecto.Migration

  @text_types ["answerBlock", "lueckentext"]

  def up do
    alter table(:tasks) do
      add :correction_config, :map, null: false, default: %{}
    end

    flush()

    %{rows: rows} = repo().query!("SELECT id, content, self_check_off FROM tasks")

    for [id, content, off] <- rows, is_map(content) do
      {new_content, config} = convert(content, off)

      if new_content == content do
        repo().query!("UPDATE tasks SET correction_config = $1 WHERE id = $2", [config, id])
      else
        repo().query!(
          "UPDATE tasks SET correction_config = $1, content = $2 WHERE id = $3",
          [config, new_content, id]
        )
      end
    end
  end

  def down do
    alter table(:tasks) do
      remove :correction_config
    end
  end

  @doc """
  One unit's content and its correction config, from its old content and its
  `self_check_off` list. Public for the test only.
  """
  def convert(content, self_check_off) do
    new_content =
      content
      |> wrap_loose_answers()
      |> Tasky.ExamDoc.ensure_part_ids()

    {new_content, correction_config(new_content, MapSet.new(self_check_off || []))}
  end

  # Inserts a question heading before the first top-level node of the preamble
  # that holds an answer field. Nothing to do when the preamble has none.
  defp wrap_loose_answers(content) do
    preamble = Tasky.ExamDoc.content_preamble(content, "answer_fields")

    case Enum.find_index(preamble, &has_answer?/1) do
      nil ->
        content

      index ->
        nodes = Map.get(content, "content", [])

        heading = %{
          "type" => "heading",
          "attrs" => %{"level" => 3},
          "content" => [%{"type" => "text", "text" => "Aufgabe"}]
        }

        # The preamble is the document's head, so its index is the document's.
        Map.put(content, "content", List.insert_at(nodes, index, heading))
    end
  end

  defp has_answer?(node),
    do: MapSet.size(Tasky.Correction.AnswerKey.block_ids(%{"content" => [node]})) > 0

  defp correction_config(content, off) do
    for part <- Tasky.ExamDoc.split_content_into_parts(content, "answer_fields"), into: %{} do
      text_ids =
        for block <- Tasky.AI.NodePatcher.list_answer_blocks(part.nodes),
            block.type in @text_types,
            block.answer_id,
            do: block.answer_id

      auto? = text_ids == [] or Enum.any?(text_ids, &(not MapSet.member?(off, &1)))

      {part.id,
       %{
         "auto_correct" => auto?,
         "ignore_case" => auto?,
         "ignore_spelling" => false,
         "ignore_punctuation" => false,
         "checkbox_scoring" => "per_checkbox"
       }}
    end
  end
end
