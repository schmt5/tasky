defmodule Tasky.TiptapMarkdownTest do
  use ExUnit.Case, async: true

  alias Tasky.TiptapMarkdown

  defp doc(nodes), do: %{"type" => "doc", "content" => nodes}
  defp md(nodes, opts \\ []), do: TiptapMarkdown.to_markdown(doc(nodes), opts)
  defp text(string), do: %{"type" => "text", "text" => string}
  defp paragraph(content), do: %{"type" => "paragraph", "content" => content}

  describe "empty and malformed input" do
    test "returns an empty string for nil, empty and unknown shapes" do
      assert TiptapMarkdown.to_markdown(nil) == ""
      assert TiptapMarkdown.to_markdown(%{}) == ""
      assert TiptapMarkdown.to_markdown("nonsense") == ""
      assert TiptapMarkdown.to_markdown(doc([])) == ""
    end

    test "an unknown node type does not crash and its text survives" do
      assert md([%{"type" => "someFutureNode", "content" => [paragraph([text("Inhalt")])]}]) ==
               "Inhalt"
    end

    test "an empty paragraph produces no blank block" do
      assert md([paragraph([text("A")]), paragraph([]), paragraph([text("B")])]) == "A\n\nB"
    end
  end

  describe "headings and paragraphs" do
    test "heading level maps to hash count and partId is ignored" do
      nodes = [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3, "partId" => "q-abc"},
          "content" => [text("Frage 1")]
        }
      ]

      assert md(nodes) == "### Frage 1"
    end

    test "a heading with an unusable level falls back to h1" do
      assert md([%{"type" => "heading", "attrs" => %{}, "content" => [text("T")]}]) == "# T"
    end

    test "blocks are separated by a blank line" do
      assert md([paragraph([text("Eins")]), paragraph([text("Zwei")])]) == "Eins\n\nZwei"
    end

    test "hardBreak becomes a markdown line break" do
      assert md([paragraph([text("Eins"), %{"type" => "hardBreak"}, text("Zwei")])]) ==
               "Eins  \nZwei"
    end
  end

  describe "marks" do
    defp marked(string, marks), do: md([paragraph([Map.put(text(string), "marks", marks)])])

    test "bold, italic, strike and code" do
      assert marked("fett", [%{"type" => "bold"}]) == "**fett**"
      assert marked("kursiv", [%{"type" => "italic"}]) == "*kursiv*"
      assert marked("weg", [%{"type" => "strike"}]) == "~~weg~~"
      assert marked("x = 1", [%{"type" => "code"}]) == "`x = 1`"
    end

    test "links render with their href" do
      marks = [%{"type" => "link", "attrs" => %{"href" => "https://example.com"}}]
      assert marked("hier", marks) == "[hier](https://example.com)"
    end

    test "decorative marks are dropped but keep their text" do
      assert marked("bunt", [%{"type" => "highlight", "attrs" => %{"color" => "#ff0"}}]) == "bunt"
      assert marked("rot", [%{"type" => "textStyle", "attrs" => %{"color" => "#f00"}}]) == "rot"
      assert marked("Kommentar", [%{"type" => "teacherComment"}]) == "Kommentar"
      assert marked("unter", [%{"type" => "underline"}]) == "unter"
    end

    test "delimiters hug the text, keeping surrounding spaces outside" do
      assert marked(" fett ", [%{"type" => "bold"}]) == "**fett**"
      assert marked("   ", [%{"type" => "bold"}]) == ""
    end

    test "stacked marks nest" do
      assert marked("beides", [%{"type" => "bold"}, %{"type" => "italic"}]) == "***beides***"
    end
  end

  describe "lists" do
    defp list(type, items) do
      %{
        "type" => type,
        "content" =>
          Enum.map(items, fn item ->
            %{"type" => "listItem", "content" => [paragraph([text(item)])]}
          end)
      }
    end

    test "bullet and ordered lists" do
      assert md([list("bulletList", ["A", "B"])]) == "- A\n- B"
      assert md([list("orderedList", ["A", "B"])]) == "1. A\n2. B"
    end

    test "an ordered list honours its start attribute" do
      ordered = list("orderedList", ["A", "B"]) |> Map.put("attrs", %{"start" => 5})
      assert md([ordered]) == "5. A\n6. B"
    end

    test "nested lists are indented under their parent item" do
      nested = %{
        "type" => "bulletList",
        "content" => [
          %{
            "type" => "listItem",
            "content" => [paragraph([text("Oben")]), list("bulletList", ["Unten"])]
          }
        ]
      }

      assert md([nested]) == "- Oben\n\n  - Unten"
    end

    test "task list items render as checkboxes" do
      nodes = [
        %{
          "type" => "taskList",
          "content" => [
            %{
              "type" => "taskItem",
              "attrs" => %{"checked" => true, "answerId" => 1},
              "content" => [paragraph([text("Erledigt")])]
            },
            %{
              "type" => "taskItem",
              "attrs" => %{"checked" => false},
              "content" => [paragraph([text("Offen")])]
            }
          ]
        }
      ]

      assert md(nodes) == "- [x] Erledigt\n- [ ] Offen"
    end
  end

  describe "answer nodes" do
    test "an empty lueckentext becomes a blank marker inside the sentence" do
      nodes = [
        paragraph([
          text("Die Hauptstadt ist "),
          %{"type" => "lueckentext", "attrs" => %{"answerId" => 123}},
          text(".")
        ])
      ]

      assert md(nodes) == "Die Hauptstadt ist [____]."
    end

    test "a filled lueckentext keeps its content" do
      nodes = [
        paragraph([
          %{"type" => "lueckentext", "attrs" => %{"answerId" => 1}, "content" => [text("Bern")]}
        ])
      ]

      assert md(nodes) == "[____: Bern]"
    end

    test "an empty answerBlock is just the marker" do
      nodes = [
        %{
          "type" => "answerBlock",
          "attrs" => %{"answerId" => 7},
          "content" => [%{"type" => "paragraph"}]
        }
      ]

      assert md(nodes) == "_[Antwortfeld]_"
    end

    test "a prefilled answerBlock keeps its content below the marker" do
      nodes = [
        %{
          "type" => "answerBlock",
          "attrs" => %{"answerId" => 7},
          "content" => [paragraph([text("Vorgabe")])]
        }
      ]

      assert md(nodes) == "_[Antwortfeld]_\n\nVorgabe"
    end
  end

  describe "blocks with structure" do
    test "blockquote prefixes every line" do
      nodes = [
        %{"type" => "blockquote", "content" => [paragraph([text("A")]), paragraph([text("B")])]}
      ]

      assert md(nodes) == "> A\n>\n> B"
    end

    test "callout renders as a labelled blockquote" do
      nodes = [
        %{
          "type" => "callout",
          "attrs" => %{"color" => "red"},
          "content" => [paragraph([text("Achtung")])]
        }
      ]

      assert md(nodes) == "> **Hinweis**\n>\n> Achtung"
    end

    test "code block keeps its text verbatim with the language fence" do
      nodes = [
        %{
          "type" => "codeBlock",
          "attrs" => %{"language" => "elixir"},
          "content" => [text("IO.puts(:hi)")]
        }
      ]

      assert md(nodes) == "```elixir\nIO.puts(:hi)\n```"
    end

    test "horizontal rule" do
      assert md([%{"type" => "horizontalRule"}]) == "---"
    end
  end

  describe "images" do
    defp image(attrs), do: %{"type" => "image", "attrs" => attrs}

    test "a root-relative source is made absolute with base_url" do
      nodes = [image(%{"src" => "/uploads/tasks/1/a.png", "alt" => "Skizze"})]

      assert md(nodes, base_url: "https://tasky.test/") ==
               "![Skizze](https://tasky.test/uploads/tasks/1/a.png)"
    end

    test "an external source is left untouched and a missing alt is empty" do
      assert md([image(%{"src" => "https://cdn.test/a.png"})], base_url: "https://tasky.test") ==
               "![](https://cdn.test/a.png)"
    end

    test "an image without a source is skipped" do
      assert md([image(%{"alt" => "kaputt"})]) == ""
    end
  end

  describe "tables" do
    defp cell(type, string), do: %{"type" => type, "content" => [paragraph([text(string)])]}
    defp row(cells), do: %{"type" => "tableRow", "content" => cells}

    test "a table with a header row renders as GFM" do
      nodes = [
        %{
          "type" => "table",
          "content" => [
            row([cell("tableHeader", "Begriff"), cell("tableHeader", "Bedeutung")]),
            row([cell("tableCell", "API"), cell("tableCell", "Schnittstelle")])
          ]
        }
      ]

      assert md(nodes) ==
               """
               | Begriff | Bedeutung |
               | --- | --- |
               | API | Schnittstelle |
               """
               |> String.trim()
    end

    test "a header-less table gets an empty header so it still parses" do
      nodes = [%{"type" => "table", "content" => [row([cell("tableCell", "A")])]}]

      assert md(nodes) == "|  |\n| --- |\n| A |"
    end

    test "an answer node inside a cell is rendered inline" do
      answer_cell = %{
        "type" => "tableCell",
        "content" => [
          paragraph([%{"type" => "lueckentext", "attrs" => %{"answerId" => 1}}])
        ]
      }

      nodes = [
        %{
          "type" => "table",
          "content" => [
            row([cell("tableHeader", "Begriff"), cell("tableHeader", "Antwort")]),
            row([cell("tableCell", "API"), answer_cell])
          ]
        }
      ]

      assert md(nodes) =~ "| API | [____] |"
    end

    test "pipes in cell text are escaped and short rows are padded" do
      nodes = [
        %{
          "type" => "table",
          "content" => [
            row([cell("tableHeader", "A"), cell("tableHeader", "B")]),
            row([cell("tableCell", "x | y")])
          ]
        }
      ]

      assert md(nodes) == "| A | B |\n| --- | --- |\n| x \\| y |  |"
    end
  end
end
