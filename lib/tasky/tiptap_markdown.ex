defmodule Tasky.TiptapMarkdown do
  @moduledoc """
  Pure Tiptap document → Markdown. Plain maps in, a string out — no `Repo`,
  no structs, same shape as `Tasky.ExamDoc`.

  This is **not** a rendering path for the UI. The visual truth of a document
  stays the React viewer, which is the only place that renders Tiptap JSON for
  humans. What this module produces is a deliberately lossy text extraction for
  machines: the public course export that a teacher hands to an AI tool.

  What is dropped on purpose, because Markdown has no equivalent and no LLM
  needs it: `underline`, `highlight`, `textStyle`/`color`, the correction-only
  `teacherComment` mark, callout colours, table `colspan`/`rowspan`, and
  `attrs.partId` / `attrs.answerId`.

  Answer-bearing nodes (`answerBlock`, `lueckentext`, `taskItem`) are **not**
  treated as leaves here, unlike in `Tasky.Correction.AnswerKey`: in a learning
  unit those nodes carry the exercise text itself, so their content is exported
  and only annotated with a marker.

  Text is not Markdown-escaped (only `|` inside table cells is). Course
  material reads better with the odd literal asterisk than with backslashes
  sprinkled through every sentence.

  ## Options

    * `:base_url` — origin prepended to root-relative image sources, so that
      `/uploads/tasks/1/x.png` becomes a URL an external fetcher can resolve.
  """

  @doc """
  Converts a Tiptap document (or a bare node list) to a Markdown string.
  Returns `""` for anything empty or unrecognisable.
  """
  def to_markdown(doc, opts \\ [])

  def to_markdown(%{"content" => nodes}, opts) when is_list(nodes) do
    blocks(nodes, context(opts))
  end

  def to_markdown(nodes, opts) when is_list(nodes) do
    blocks(nodes, context(opts))
  end

  def to_markdown(_doc, _opts), do: ""

  defp context(opts) do
    %{base_url: opts |> Keyword.get(:base_url, "") |> String.trim_trailing("/")}
  end

  # --- Blocks ---------------------------------------------------------------

  defp blocks(nodes, ctx) when is_list(nodes) do
    nodes
    |> Enum.map(&block(&1, ctx))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp blocks(_nodes, _ctx), do: ""

  # Trimmed on both ends: four leading spaces would turn a paragraph into an
  # indented code block.
  defp block(%{"type" => "paragraph"} = node, ctx) do
    node |> children() |> inlines(ctx) |> String.trim()
  end

  defp block(%{"type" => "heading"} = node, ctx) do
    level = node |> attrs() |> Map.get("level", 1) |> clamp_level()
    text = node |> children() |> inlines(ctx) |> String.trim()

    if text == "", do: "", else: String.duplicate("#", level) <> " " <> text
  end

  defp block(%{"type" => "blockquote"} = node, ctx) do
    node |> children() |> blocks(ctx) |> prefix_lines("> ")
  end

  defp block(%{"type" => "codeBlock"} = node, ctx) do
    language = node |> attrs() |> Map.get("language") |> to_language()
    "```" <> language <> "\n" <> plain_text(children(node), ctx) <> "\n```"
  end

  defp block(%{"type" => "bulletList"} = node, ctx) do
    node |> children() |> list_items(fn _index -> "- " end, ctx)
  end

  defp block(%{"type" => "orderedList"} = node, ctx) do
    start = node |> attrs() |> Map.get("start", 1)
    start = if is_integer(start), do: start, else: 1

    node |> children() |> list_items(&"#{start + &1 - 1}. ", ctx)
  end

  defp block(%{"type" => "taskList"} = node, ctx) do
    node
    |> children()
    |> Enum.map_join("\n", fn item ->
      marker = if item |> attrs() |> Map.get("checked") == true, do: "- [x] ", else: "- [ ] "
      list_item(marker, blocks(children(item), ctx))
    end)
  end

  # A stray taskItem outside a taskList still has to render something.
  defp block(%{"type" => "taskItem"} = node, ctx) do
    block(%{"type" => "taskList", "content" => [node]}, ctx)
  end

  defp block(%{"type" => "image"} = node, ctx), do: image(node, ctx)

  defp block(%{"type" => "table"} = node, ctx), do: table(children(node), ctx)

  defp block(%{"type" => "horizontalRule"}, _ctx), do: "---"

  defp block(%{"type" => "callout"} = node, ctx) do
    body = node |> children() |> blocks(ctx)
    inner = if body == "", do: "**Hinweis**", else: "**Hinweis**\n\n" <> body

    prefix_lines(inner, "> ")
  end

  defp block(%{"type" => "answerBlock"} = node, ctx) do
    body = node |> children() |> blocks(ctx)

    if body == "", do: "_[Antwortfeld]_", else: "_[Antwortfeld]_\n\n" <> body
  end

  # Unknown node: never crash the export, just walk through it. A new editor
  # extension degrades to its text rather than taking the whole course down.
  defp block(%{"content" => content}, ctx) when is_list(content), do: blocks(content, ctx)

  defp block(_node, _ctx), do: ""

  defp clamp_level(level) when is_integer(level) and level >= 1 and level <= 6, do: level
  defp clamp_level(_level), do: 1

  defp to_language(language) when is_binary(language), do: language
  defp to_language(_language), do: ""

  # --- Lists ----------------------------------------------------------------

  defp list_items(items, marker_fun, ctx) do
    items
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {item, index} ->
      list_item(marker_fun.(index), blocks(children(item), ctx))
    end)
  end

  # Continuation lines are indented by the marker width so nested lists and
  # multi-paragraph items stay inside their item.
  defp list_item(marker, ""), do: String.trim_trailing(marker)

  defp list_item(marker, body) do
    padding = String.duplicate(" ", String.length(marker))

    body
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.map_join("\n", fn
      {line, 0} -> marker <> line
      {"", _index} -> ""
      {line, _index} -> padding <> line
    end)
  end

  # --- Tables ---------------------------------------------------------------

  defp table([], _ctx), do: ""

  defp table(rows, ctx) do
    cells = Enum.map(rows, fn row -> Enum.map(children(row), &cell_text(&1, ctx)) end)
    width = cells |> Enum.map(&length/1) |> Enum.max(fn -> 0 end)

    if width == 0 do
      ""
    else
      {header, body} = split_header(rows, cells, width)
      separator = "| " <> Enum.map_join(1..width, " | ", fn _ -> "---" end) <> " |"

      Enum.join([table_row(header), separator | Enum.map(body, &table_row/1)], "\n")
    end
  end

  # GFM needs a header row. A table whose first row holds no `tableHeader`
  # cells gets an empty one so the rest still parses as a table.
  defp split_header(rows, [first_cells | rest_cells], width) do
    if rows |> List.first() |> children() |> Enum.any?(&(Map.get(&1, "type") == "tableHeader")) do
      {pad(first_cells, width), Enum.map(rest_cells, &pad(&1, width))}
    else
      {List.duplicate("", width), Enum.map([first_cells | rest_cells], &pad(&1, width))}
    end
  end

  defp pad(cells, width), do: cells ++ List.duplicate("", width - length(cells))

  defp table_row(cells), do: "| " <> Enum.join(cells, " | ") <> " |"

  defp cell_text(cell, ctx) do
    cell
    |> children()
    |> blocks(ctx)
    |> String.replace(~r/\s*\n+\s*/, " ")
    |> String.replace("|", "\\|")
    |> String.trim()
  end

  # --- Inline ---------------------------------------------------------------

  defp inlines(nodes, ctx) when is_list(nodes) do
    Enum.map_join(nodes, "", &inline(&1, ctx))
  end

  defp inlines(_nodes, _ctx), do: ""

  defp inline(%{"type" => "text", "text" => text} = node, ctx) when is_binary(text) do
    apply_marks(text, Map.get(node, "marks"), ctx)
  end

  defp inline(%{"type" => "hardBreak"}, _ctx), do: "  \n"

  defp inline(%{"type" => "image"} = node, ctx), do: image(node, ctx)

  defp inline(%{"type" => "lueckentext"} = node, ctx) do
    case node |> children() |> inlines(ctx) |> String.trim() do
      "" -> "[____]"
      filled -> "[____: " <> filled <> "]"
    end
  end

  defp inline(%{"content" => content}, ctx) when is_list(content), do: inlines(content, ctx)

  defp inline(_node, _ctx), do: ""

  defp apply_marks(text, marks, ctx) when is_list(marks) do
    Enum.reduce(marks, text, &apply_mark(&2, &1, ctx))
  end

  defp apply_marks(text, _marks, _ctx), do: text

  defp apply_mark(text, %{"type" => "bold"}, _ctx), do: wrap(text, "**")
  defp apply_mark(text, %{"type" => "italic"}, _ctx), do: wrap(text, "*")
  defp apply_mark(text, %{"type" => "strike"}, _ctx), do: wrap(text, "~~")
  defp apply_mark(text, %{"type" => "code"}, _ctx), do: wrap(text, "`")

  defp apply_mark(text, %{"type" => "link", "attrs" => %{"href" => href}}, _ctx)
       when is_binary(href) and href != "" do
    if String.trim(text) == "", do: text, else: "[" <> text <> "](" <> href <> ")"
  end

  defp apply_mark(text, _mark, _ctx), do: text

  # Delimiters must hug the text: `** bold **` is not bold in Markdown.
  defp wrap(text, delimiter) do
    case Regex.run(~r/\A(\s*)(.*?)(\s*)\z/s, text, capture: :all_but_first) do
      [_leading, "", _trailing] -> text
      [leading, core, trailing] -> leading <> delimiter <> core <> delimiter <> trailing
      _no_match -> text
    end
  end

  # --- Shared helpers -------------------------------------------------------

  defp image(node, ctx) do
    node_attrs = attrs(node)

    case Map.get(node_attrs, "src") do
      src when is_binary(src) and src != "" ->
        alt = node_attrs |> Map.get("alt") |> to_string()
        "![" <> alt <> "](" <> absolute_url(src, ctx) <> ")"

      _missing ->
        ""
    end
  end

  defp absolute_url("/" <> _rest = src, %{base_url: base}) when base != "", do: base <> src
  defp absolute_url(src, _ctx), do: src

  defp plain_text(nodes, ctx) when is_list(nodes) do
    Enum.map_join(nodes, "", fn
      %{"type" => "text", "text" => text} when is_binary(text) -> text
      %{"type" => "hardBreak"} -> "\n"
      %{"content" => content} when is_list(content) -> plain_text(content, ctx)
      _node -> ""
    end)
  end

  defp plain_text(_nodes, _ctx), do: ""

  defp prefix_lines("", _prefix), do: ""

  defp prefix_lines(text, prefix) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> String.trim_trailing(prefix)
      line -> prefix <> line
    end)
  end

  defp children(node) when is_map(node) do
    case Map.get(node, "content") do
      content when is_list(content) -> content
      _missing -> []
    end
  end

  defp children(_node), do: []

  defp attrs(node) when is_map(node) do
    case Map.get(node, "attrs") do
      attrs when is_map(attrs) -> attrs
      _missing -> %{}
    end
  end

  defp attrs(_node), do: %{}
end
