defmodule Tasky.Correction.AnswerKeyTest do
  use ExUnit.Case, async: true

  alias Tasky.Correction.AnswerKey

  describe "ensure_ids/1" do
    test "assigns unique ids to answer nodes lacking one and keeps existing ids" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{"type" => "answerBlock", "attrs" => %{"answerId" => 1234}, "content" => []},
          %{"type" => "paragraph", "content" => [%{"type" => "lueckentext"}]},
          %{"type" => "taskList", "content" => [%{"type" => "taskItem", "attrs" => %{"checked" => false}}]}
        ]
      }

      result = AnswerKey.ensure_ids(doc)
      ids = collect_ids(result)

      assert 1234 in ids or "1234" in Enum.map(ids, &to_string/1)
      assert length(ids) == 3
      assert Enum.uniq(Enum.map(ids, &to_string/1)) |> length() == 3
    end
  end

  describe "split/1 and merge/2 round-trip" do
    test "answerBlock: answer content goes to map, content is blanked, merge restores" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "answerBlock",
            "attrs" => %{"answerId" => 1111},
            "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Paris"}]}]
          }
        ]
      }

      {content, answers} = AnswerKey.split(doc)

      assert answers["1111"] == [
               %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Paris"}]}
             ]

      [block] = content["content"]
      assert block["content"] == [%{"type" => "paragraph"}]

      assert AnswerKey.merge(content, answers) == doc
    end

    test "lueckentext: inline answer content round-trips, blanked node drops content" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{"type" => "text", "text" => "Die Hauptstadt ist "},
              %{
                "type" => "lueckentext",
                "attrs" => %{"answerId" => 2222},
                "content" => [%{"type" => "text", "text" => "Bern"}]
              }
            ]
          }
        ]
      }

      {content, answers} = AnswerKey.split(doc)

      assert answers["2222"] == [%{"type" => "text", "text" => "Bern"}]

      [%{"content" => [_text, blank_lt]}] = content["content"]
      refute Map.has_key?(blank_lt, "content")

      assert AnswerKey.merge(content, answers) == doc
    end

    test "taskItem: checked state is the answer, blanked node is unchecked" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "taskList",
            "content" => [
              %{
                "type" => "taskItem",
                "attrs" => %{"answerId" => 3333, "checked" => true},
                "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Wahr"}]}]
              }
            ]
          }
        ]
      }

      {content, answers} = AnswerKey.split(doc)

      assert answers["3333"] == true

      [%{"content" => [task]}] = content["content"]
      assert task["attrs"]["checked"] == false
      # label text stays in content
      assert task["content"] == [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Wahr"}]}]

      assert AnswerKey.merge(content, answers) == doc
    end

    test "split assigns ids when missing so the round-trip still works" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "lueckentext", "content" => [%{"type" => "text", "text" => "x"}]}]}
        ]
      }

      # Seed ids once so the random assignment is shared between split and the
      # expected value (split would otherwise re-generate them internally, but
      # ids already present are preserved).
      doc_with_ids = AnswerKey.ensure_ids(doc)
      {content, answers} = AnswerKey.split(doc_with_ids)

      assert map_size(answers) == 1
      assert AnswerKey.merge(content, answers) == doc_with_ids
    end
  end

  describe "merge/2 with empty or unrelated answers" do
    test "returns content unchanged when answers is empty" do
      content = %{"type" => "doc", "content" => [%{"type" => "paragraph"}]}
      assert AnswerKey.merge(content, %{}) == content
    end
  end

  describe "image nodes" do
    test "pass through ensure_ids and split untouched (not treated as answers)" do
      image = %{"type" => "image", "attrs" => %{"src" => "/uploads/exams/1/x.png"}}
      doc = %{"type" => "doc", "content" => [image, %{"type" => "paragraph", "content" => []}]}

      # No answerId is added to the image node.
      assert AnswerKey.ensure_ids(doc)["content"] |> hd() == image

      # Splitting yields no answers and leaves the image in place.
      {content, answers} = AnswerKey.split(doc)
      assert hd(content["content"]) == image
      assert answers == %{}
    end
  end

  defp collect_ids(%{"content" => content}) do
    Enum.flat_map(content, fn
      %{"type" => t} = node when t in ["answerBlock", "lueckentext", "taskItem"] ->
        case get_in(node, ["attrs", "answerId"]) do
          nil -> []
          id -> [id]
        end

      %{"content" => _} = node ->
        collect_ids(node)

      _ ->
        []
    end)
  end
end
