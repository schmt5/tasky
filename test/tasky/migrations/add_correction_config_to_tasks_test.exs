Code.require_file(
  "../../../priv/repo/migrations/20261109153801_add_correction_config_to_tasks.exs",
  __DIR__
)

defmodule Tasky.Migrations.AddCorrectionConfigToTasksTest do
  @moduledoc """
  The conversion of a learning unit from answer fields excluded one by one
  (`self_check_off`) to correction options per question. Live data: every
  unit must keep checking what it checked before.
  """
  use ExUnit.Case, async: true

  alias Tasky.Repo.Migrations.AddCorrectionConfigToTasks, as: Migration

  defp question(id),
    do: %{
      "type" => "heading",
      "attrs" => %{"level" => 3, "partId" => id},
      "content" => [%{"type" => "text", "text" => "Frage"}]
    }

  defp answer(id),
    do: %{"type" => "answerBlock", "attrs" => %{"answerId" => id}, "content" => []}

  defp checkbox(id),
    do: %{
      "type" => "taskList",
      "content" => [%{"type" => "taskItem", "attrs" => %{"answerId" => id}, "content" => []}]
    }

  defp intro, do: %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Intro"}]}

  defp doc(nodes), do: %{"type" => "doc", "content" => nodes}

  test "puts a question before answer fields that stand outside one" do
    {content, config} = Migration.convert(doc([intro(), answer("a1"), answer("a2")]), [])

    assert [%{"type" => "paragraph"}, heading, %{"attrs" => %{"answerId" => "a1"}}, _a2] =
             content["content"]

    assert %{"type" => "heading", "attrs" => %{"level" => 3, "partId" => part_id}} = heading
    assert %{^part_id => %{"auto_correct" => true, "ignore_case" => true}} = config
  end

  test "leaves a unit whose fields all stand under questions as it is" do
    original = doc([intro(), question("q-1"), answer("a1")])

    assert {^original, %{"q-1" => %{"auto_correct" => true}}} = Migration.convert(original, [])
  end

  test "keeps a question checked while one of its text fields was" do
    original = doc([question("q-1"), answer("a1"), answer("a2"), question("q-2"), answer("a3")])

    {_content, config} = Migration.convert(original, ["a2", "a3"])

    assert %{"auto_correct" => true, "ignore_case" => true} = config["q-1"]
    assert %{"auto_correct" => false, "ignore_case" => false} = config["q-2"]
  end

  test "a question of only ticks stays checked" do
    {_content, config} = Migration.convert(doc([question("q-1"), checkbox("c1")]), ["c1"])

    assert %{"auto_correct" => true} = config["q-1"]
  end

  test "gives a heading without partId a stable one" do
    heading = %{"type" => "heading", "attrs" => %{"level" => 3}, "content" => []}

    {content, config} = Migration.convert(doc([heading, answer("a1")]), [])

    assert [%{"attrs" => %{"partId" => part_id}}, _] = content["content"]
    assert Map.keys(config) == [part_id]
  end
end
