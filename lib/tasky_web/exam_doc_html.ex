defmodule TaskyWeb.ExamDocHTML do
  @moduledoc """
  Tiptap-Dokument → HTML für die Lernendenansicht, mit echten Eingabefeldern.

  Lehrpersonen schreiben im Tiptap-Editor; Lernende sehen den Inhalt als
  normales HTML. Die Antwortknoten werden zu nativen Feldern:

    * `lueckentext` → `<input type="text">`
    * `answerBlock` → `<textarea>` (Klartext, siehe
      `Tasky.Correction.PlainAnswers`)
    * `taskItem` → `<input type="checkbox">`
    * `choice` → `<input type="radio">`, gruppiert über die `groupId`

  Die Felder tragen `data-answer-id` bzw. `data-group-id`; der Hook
  `ExamAnswersForm` liest sie aus und speichert. Ein `name` haben nur die
  Radios — der Browser braucht ihn, um die Gruppe zu bilden.

  Das HTML wird als Iodata gebaut, nicht in HEEx: Zwischen Inline-Elementen
  darf kein Leerraum entstehen, den ein Template-Formatter einfügen könnte
  („**fett**,“ würde sonst zu „fett ,“). Jeder Text und jedes Attribut geht
  durch `Phoenix.HTML`.

  Wie `priv/typst/tiptap.typ` und `Tasky.TiptapMarkdown` ist der Renderer
  total: Ein unbekannter Knoten rendert seine Kinder. Ein neuer Knotentyp im
  Editor braucht hier trotzdem einen eigenen Zweig.
  """

  import Phoenix.HTML, only: [html_escape: 1]

  alias Tasky.Correction.Choice
  alias Tasky.Correction.PlainAnswers

  @doc """
  Rendert `doc` zu sicherem HTML.

  Optionen:

    * `:id` — Präfix für Element-ids und Radio-Namen (Pflicht, eindeutig pro
      Seite).
    * `:disabled` — alle Felder gesperrt (Rücklese-Ansicht).
  """
  def render(doc, opts) do
    id = Keyword.fetch!(opts, :id)
    nodes = children(doc)

    ctx = %{
      id: id,
      disabled: Keyword.get(opts, :disabled, false),
      choice_labels: choice_labels(nodes),
      question: nil,
      gap: 0,
      in_answer: false
    }

    {html, _ctx} = top_level(nodes, ctx)
    {:safe, html}
  end

  # Die Frage, zu der ein Feld gehört, ist die letzte Frage-Überschrift (h3
  # auf oberster Ebene, wie in `Tasky.ExamDoc`). Sie benennt die Felder für
  # Screenreader.
  defp top_level(nodes, ctx) do
    Enum.map_reduce(nodes, ctx, fn node, ctx ->
      ctx =
        if Tasky.ExamDoc.question_heading?(node),
          do: %{ctx | question: node |> children() |> plain_text() |> String.trim(), gap: 0},
          else: ctx

      node(node, ctx)
    end)
  end

  defp nodes(nodes, ctx), do: Enum.map_reduce(nodes, ctx, &node/2)

  # --- Blöcke ----------------------------------------------------------------

  defp node(%{"type" => "paragraph"} = n, ctx) do
    case children(n) do
      [] -> {"<p><br></p>", ctx}
      content -> wrap("p", [], content, ctx)
    end
  end

  defp node(%{"type" => "heading"} = n, ctx) do
    level =
      case attrs(n)["level"] do
        level when level in 1..6 -> level
        _ -> 1
      end

    wrap("h#{level}", [], children(n), ctx)
  end

  defp node(%{"type" => "blockquote"} = n, ctx), do: wrap("blockquote", [], children(n), ctx)

  defp node(%{"type" => "callout"} = n, ctx) do
    color = attrs(n)["color"]
    color = if color in ~w(red yellow green blue violet), do: color, else: "yellow"
    wrap("div", [class: "callout", "data-color": color], children(n), ctx)
  end

  defp node(%{"type" => "bulletList"} = n, ctx), do: wrap("ul", [], children(n), ctx)

  defp node(%{"type" => "orderedList"} = n, ctx) do
    start =
      case attrs(n)["start"] do
        start when is_integer(start) and start != 1 -> [start: start]
        _ -> []
      end

    wrap("ol", start, children(n), ctx)
  end

  defp node(%{"type" => "listItem"} = n, ctx), do: wrap("li", [], children(n), ctx)

  defp node(%{"type" => "taskList"} = n, ctx),
    do: wrap("ul", ["data-type": "taskList"], children(n), ctx)

  defp node(%{"type" => "taskItem"} = n, ctx), do: task_item(n, ctx)

  defp node(%{"type" => "codeBlock"} = n, ctx) do
    {["<pre><code>", escape(plain_text(children(n))), "</code></pre>"], ctx}
  end

  defp node(%{"type" => "horizontalRule"}, ctx), do: {"<hr>", ctx}

  defp node(%{"type" => "table"} = n, ctx) do
    {rows, ctx} = nodes(children(n), ctx)
    {[~s(<div class="tableWrapper"><table><tbody>), rows, "</tbody></table></div>"], ctx}
  end

  defp node(%{"type" => "tableRow"} = n, ctx), do: wrap("tr", [], children(n), ctx)

  defp node(%{"type" => type} = n, ctx) when type in ["tableCell", "tableHeader"] do
    tag = if type == "tableHeader", do: "th", else: "td"

    span =
      Enum.flat_map(["colspan", "rowspan"], fn key ->
        case attrs(n)[key] do
          value when is_integer(value) and value > 1 -> [{key, value}]
          _ -> []
        end
      end)

    wrap(tag, span, children(n), ctx)
  end

  defp node(%{"type" => "image"} = n, ctx) do
    case attrs(n)["src"] do
      "/" <> _ = src ->
        {["<img", attributes_escape(src: src, alt: attrs(n)["alt"] || ""), ">"], ctx}

      "https://" <> _ = src ->
        {["<img", attributes_escape(src: src, alt: attrs(n)["alt"] || ""), ">"], ctx}

      _ ->
        {"", ctx}
    end
  end

  defp node(%{"type" => type} = n, %{in_answer: true} = ctx)
       when type in ["answerBlock", "lueckentext", "taskItem", "choice"],
       do: nodes(children(n), ctx)

  defp node(%{"type" => "answerBlock"} = n, ctx), do: answer_block(n, ctx)

  # Nur für die Rückgabe gedacht — die Lernendenansicht zeigt sie nie.
  defp node(%{"type" => "solutionHint"}, ctx), do: {"", ctx}

  # --- Inline ----------------------------------------------------------------

  defp node(%{"type" => "text", "text" => text} = n, ctx) when is_binary(text) do
    {n
     |> Map.get("marks", [])
     |> List.wrap()
     |> Enum.reverse()
     |> Enum.reduce(escape(text), &mark/2), ctx}
  end

  defp node(%{"type" => "hardBreak"}, ctx), do: {"<br>", ctx}

  defp node(%{"type" => "lueckentext"} = n, ctx), do: gap(n, ctx)

  defp node(%{"type" => "choice"} = n, ctx), do: radio(n, ctx)

  # Unbekannter Knoten: nie abstürzen, nur hindurchgehen.
  defp node(%{"content" => content}, ctx) when is_list(content), do: nodes(content, ctx)

  defp node(_node, ctx), do: {"", ctx}

  defp mark(%{"type" => "bold"}, html), do: ["<strong>", html, "</strong>"]
  defp mark(%{"type" => "italic"}, html), do: ["<em>", html, "</em>"]
  defp mark(%{"type" => "underline"}, html), do: ["<u>", html, "</u>"]
  defp mark(%{"type" => "strike"}, html), do: ["<s>", html, "</s>"]
  defp mark(%{"type" => "code"}, html), do: ["<code>", html, "</code>"]

  defp mark(%{"type" => "link", "attrs" => %{"href" => href}}, html) when is_binary(href) do
    if safe_href?(href) do
      [
        "<a",
        attributes_escape(href: href, target: "_blank", rel: "noopener noreferrer nofollow"),
        ">",
        html,
        "</a>"
      ]
    else
      html
    end
  end

  defp mark(%{"type" => "textStyle", "attrs" => %{"color" => color}}, html) do
    if safe_color?(color),
      do: ["<span", attributes_escape(style: "color: #{color}"), ">", html, "</span>"],
      else: html
  end

  defp mark(%{"type" => "highlight"} = m, html) do
    color = get_in(m, ["attrs", "color"])

    style =
      if safe_color?(color), do: [style: "background-color: #{color}; color: inherit"], else: []

    ["<mark", attributes_escape(style), ">", html, "</mark>"]
  end

  defp mark(_mark, html), do: html

  defp safe_href?(href), do: String.match?(href, ~r/\A(https?:|mailto:)/i)

  defp safe_color?(color) when is_binary(color),
    do: String.match?(color, ~r/\A(#[0-9a-fA-F]{3,8}|rgba?\([0-9.,\s%]+\))\z/)

  defp safe_color?(_color), do: false

  # --- Antwortfelder ---------------------------------------------------------

  defp answer_block(n, ctx) do
    case answer_id(n) do
      nil ->
        nodes(children(n), ctx)

      id ->
        attrs =
          [
            id: field_id(ctx, id),
            class: "exam-doc__block",
            rows: 3,
            maxlength: PlainAnswers.max_block_chars(),
            "data-answer-id": id,
            "aria-label": label("Antwort", ctx)
          ] ++ field_flags(ctx)

        # Ein führender Zeilenumbruch im Inhalt eines <textarea> wird vom
        # Parser verschluckt; der zusätzliche hält eine Antwort, die mit einer
        # Leerzeile beginnt, intakt.
        {[
           "<textarea",
           attributes_escape(attrs),
           ">\n",
           escape(PlainAnswers.block_text(children(n))),
           "</textarea>"
         ], ctx}
    end
  end

  defp gap(n, ctx) do
    case answer_id(n) do
      nil ->
        nodes(children(n), ctx)

      id ->
        ctx = %{ctx | gap: ctx.gap + 1}

        attrs =
          [
            type: "text",
            id: field_id(ctx, id),
            class: "exam-doc__gap",
            value: PlainAnswers.gap_text(children(n)),
            maxlength: PlainAnswers.max_gap_chars(),
            size: 1,
            "data-answer-id": id,
            "aria-label": label("Lücke #{ctx.gap}", ctx)
          ] ++ field_flags(ctx)

        {["<input", attributes_escape(attrs), ">"], ctx}
    end
  end

  defp task_item(n, ctx) do
    case answer_id(n) do
      nil ->
        wrap("li", [], children(n), ctx)

      id ->
        input =
          [
            type: "checkbox",
            id: field_id(ctx, id),
            checked: attrs(n)["checked"] == true,
            "data-answer-id": id
          ] ++ field_flags(ctx)

        # Der Text gehört ins <label>: Ein Klick darauf kreuzt an, und er ist
        # der Name der Checkbox. Ein <label> nimmt nur Inline-Inhalt, ein
        # taskItem ist aber `paragraph+` — also kommt der erste Absatz als
        # Inline-Inhalt hinein, weitere Absätze stehen darunter.
        {first, rest} =
          case children(n) do
            [%{"type" => "paragraph"} = paragraph | rest] -> {children(paragraph), rest}
            blocks -> {[], blocks}
          end

        # Ein taskItem ist für `AnswerKey` ein Blatt: Ein Feld darin würde nie
        # gespeichert, also wird es nur als Text gezeigt. Das hält auch das
        # <label> gültig — es darf nur ein Eingabefeld enthalten.
        {label, ctx} = nodes(first, %{ctx | in_answer: true})
        {more, ctx} = nodes(rest, ctx)
        ctx = %{ctx | in_answer: false}

        more =
          if rest == [], do: "", else: [~s(<div class="exam-doc__option-more">), more, "</div>"]

        {[
           "<li",
           attributes_escape("data-checked": attrs(n)["checked"] == true),
           ~s(><label class="exam-doc__option"><input),
           attributes_escape(input),
           "><span>",
           label,
           "</span></label>",
           more,
           "</li>"
         ], ctx}
    end
  end

  defp radio(n, ctx) do
    case {Choice.group_id(n), Choice.option_id(n)} do
      {gid, oid} when is_binary(gid) and is_binary(oid) ->
        attrs =
          [
            type: "radio",
            id: field_id(ctx, gid <> "-" <> oid),
            class: "exam-doc__radio",
            name: "#{ctx.id}-choice-#{gid}",
            value: oid,
            checked: Choice.checked?(n),
            "data-group-id": gid,
            "aria-label": Map.get(ctx.choice_labels, {gid, oid}) || "Option"
          ] ++ field_flags(ctx)

        {["<input", attributes_escape(attrs), ">"], ctx}

      _ ->
        {"", ctx}
    end
  end

  # Keine Rechtschreibhilfe und keine Autokorrektur: in einer Prüfung wären
  # das Hilfsmittel (dieselbe Regel wie `allowSpellCheck: false` im SEB).
  defp field_flags(ctx) do
    [
      spellcheck: "false",
      autocorrect: "off",
      autocapitalize: "off",
      autocomplete: "off",
      disabled: ctx.disabled
    ]
  end

  defp label(base, %{question: nil}), do: base

  defp label(base, %{question: question}),
    do: base <> " zu: " <> String.slice(question, 0, 120)

  defp field_id(ctx, id), do: "#{ctx.id}-field-#{id}"

  defp choice_labels(nodes) do
    for {gid, %{options: options}} <- Choice.groups(nodes),
        option <- options,
        into: %{},
        do: {{gid, option.option_id}, option.label}
  end

  # --- Helfer ----------------------------------------------------------------

  defp attributes_escape(attrs) do
    {:safe, html} = Phoenix.HTML.attributes_escape(attrs)
    html
  end

  defp wrap(tag, attrs, content, ctx) do
    {inner, ctx} = nodes(content, ctx)
    {["<", tag, attributes_escape(attrs), ">", inner, "</", tag, ">"], ctx}
  end

  defp escape(text), do: text |> html_escape() |> Phoenix.HTML.safe_to_string()

  defp answer_id(n) do
    case attrs(n)["answerId"] do
      nil -> nil
      id -> to_string(id)
    end
  end

  defp plain_text(nodes) when is_list(nodes) do
    Enum.map_join(nodes, "", fn
      %{"type" => "text", "text" => text} when is_binary(text) -> text
      %{"type" => "hardBreak"} -> "\n"
      %{"content" => content} when is_list(content) -> plain_text(content)
      _node -> ""
    end)
  end

  defp children(node) when is_map(node) do
    case Map.get(node, "content") do
      content when is_list(content) -> content
      _ -> []
    end
  end

  defp children(_node), do: []

  defp attrs(node) do
    case Map.get(node, "attrs") do
      attrs when is_map(attrs) -> attrs
      _ -> %{}
    end
  end
end
