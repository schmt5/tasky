defmodule Tasky.Correction.Choice do
  @moduledoc """
  Single-Choice-Auswahl: Radios (`choice`), die zusammen **eine** Frage bilden.

  Ein `choice` ist ein Inline-Atom ohne Inhalt. Es kann überall stehen — in
  einer Tabellenzelle, in einem Absatz, in einer Liste —, darum steckt die
  Gruppe nicht in der Verschachtelung, sondern im Attribut `groupId`: alle
  Radios mit derselben `groupId` sind eine Frage. Die `groupId` spielt für die
  Gruppe die Rolle der `answerId` (Musterlösung, `block_verdicts`, Punkte).
  Ein eigener Name statt `answerId`, weil die Duplikat-Logik für `answerId`
  (Einfügen, `AnswerKey.ensure_ids/1`) eine Gruppe sonst zerreissen würde.

      %{"type" => "choice",
        "attrs" => %{"groupId" => 482913, "optionId" => "o_k3f9",
                     "checked" => false, "verdict" => nil, "correct" => nil}}

  Die eine Regel, an die sich jeder positionsbasierte Walker halten muss:
  **eine Gruppe zählt einmal, an der Position ihres ersten Radios** in
  Dokumentreihenfolge. `__ai_id`, `block_points` und die Index→id-Zuordnung
  der Korrektur hängen daran, dass alle Walker gleich zählen.

  Die Musterlösung einer Gruppe ist die `optionId` des richtigen Radios, oder
  `nil` (keine Vorgabe, keine Autokorrektur).
  """

  @type_name "choice"

  @doc "Der Knotentyp eines Radios."
  def type, do: @type_name

  @doc "Die `groupId` eines Radios als String, oder `nil`."
  def group_id(node), do: string_attr(node, "groupId")

  @doc "Die `optionId` eines Radios als String, oder `nil`."
  def option_id(node), do: string_attr(node, "optionId")

  @doc "Ob das Radio gewählt ist."
  def checked?(node), do: attrs(node) |> Map.get("checked") == true

  @doc "Setzt ein Attribut; `nil` entfernt es."
  def put_attr(node, key, nil), do: Map.put(node, "attrs", Map.delete(attrs(node), key))
  def put_attr(node, key, value), do: Map.put(node, "attrs", Map.put(attrs(node), key, value))

  @doc """
  Alle Auswahlgruppen in `nodes`, als `%{group_id => group}`:

      %{options: [%{option_id:, label:, checked:, verdict:}, ...]}

  Die Optionen stehen in Dokumentreihenfolge. Das `label` einer Option ist der
  Text direkt nach dem Radio im selben Elternknoten (bis zum nächsten Radio);
  steht dort nichts und sitzt das Radio in einer Tabelle mit Kopfzeile, ist es
  die Kopfzelle derselben Spalte („analog“ / „digital“). Sonst `"Option N"`.
  """
  def groups(nodes) when is_list(nodes) do
    nodes
    |> collect(%{header: nil, col: nil}, [])
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn {gid, option}, acc ->
      Map.update(acc, gid, %{options: [option]}, &%{&1 | options: &1.options ++ [option]})
    end)
    |> Map.new(fn {gid, %{options: options}} ->
      numbered =
        options
        |> Enum.with_index(1)
        |> Enum.map(fn
          {%{label: ""} = o, n} -> %{o | label: "Option #{n}"}
          {o, _n} -> o
        end)

      {gid, %{options: numbered}}
    end)
  end

  def groups(_nodes), do: %{}

  @doc "Die `optionId`s der gewählten Radios einer Gruppe (normal: keine oder eine)."
  def checked_options(%{options: options}),
    do: for(%{checked: true, option_id: id} <- options, do: id)

  def checked_options(_group), do: []

  @doc "Das Label der Option `option_id` einer Gruppe, oder `nil`."
  def label_of(%{options: options}, option_id) when is_binary(option_id) do
    Enum.find_value(options, fn o -> o.option_id == option_id && o.label end)
  end

  def label_of(_group, _option_id), do: nil

  @doc "Das Label der gewählten Option, `\"\"` ohne (oder bei mehrdeutiger) Wahl."
  def selected_label(group) do
    case checked_options(group) do
      [id] -> label_of(group, id) || ""
      _ -> ""
    end
  end

  @doc "Das Verdikt, das an den Radios der Gruppe steht (`attrs.verdict`), oder `nil`."
  def verdict(%{options: options}), do: Enum.find_value(options, & &1.verdict)
  def verdict(_group), do: nil

  @doc """
  Hält jede Gruppe innerhalb einer Teilaufgabe. Bewertet, gespeichert und
  korrigiert wird pro Teilaufgabe; eine Gruppe, deren Radios in zwei Teilen
  stehen, bekäme in beiden ein Verdikt unter derselben id. Radios eines
  späteren Teils, deren `groupId` schon in einem früheren Teil vorkam,
  bekommen darum eine neue — alle Radios dieses Teils dieselbe neue.

  `part_start?` erkennt den Knoten, mit dem eine Teilaufgabe beginnt
  (`Tasky.ExamDoc.question_heading?/1`); `taken` sind die ids, die schon
  vergeben sind (`Tasky.Correction.AnswerKey.block_ids/1`).
  """
  def separate_by_part(%{"content" => nodes} = doc, part_start?, taken) when is_list(nodes) do
    {new_nodes, _state} =
      Enum.map_reduce(nodes, %{part: 0, owner: %{}, remap: %{}, taken: taken}, fn node, st ->
        st = if part_start?.(node), do: %{st | part: st.part + 1, remap: %{}}, else: st
        separate_node(node, st)
      end)

    Map.put(doc, "content", new_nodes)
  end

  def separate_by_part(doc, _part_start?, _taken), do: doc

  defp separate_node(%{"type" => @type_name} = node, st) do
    case group_id(node) do
      nil ->
        {node, st}

      gid ->
        case Map.fetch(st.owner, gid) do
          :error ->
            {node, %{st | owner: Map.put(st.owner, gid, st.part)}}

          {:ok, part} when part == st.part ->
            {node, st}

          {:ok, _earlier} ->
            {new_gid, st} = renamed_group(gid, st)
            {put_attr(node, "groupId", new_gid), st}
        end
    end
  end

  defp separate_node(%{"content" => content} = node, st) when is_list(content) do
    {new_content, st} = Enum.map_reduce(content, st, &separate_node/2)
    {Map.put(node, "content", new_content), st}
  end

  defp separate_node(node, st), do: {node, st}

  # The new id a group from an earlier part takes in the current one — the
  # same for all its radios here.
  defp renamed_group(gid, st) do
    case Map.fetch(st.remap, gid) do
      {:ok, new_gid} ->
        {new_gid, st}

      :error ->
        new_gid = gen_group_id(st.taken)

        {new_gid,
         %{
           st
           | remap: Map.put(st.remap, gid, new_gid),
             taken: MapSet.put(st.taken, to_string(new_gid)),
             owner: Map.put(st.owner, to_string(new_gid), st.part)
         }}
    end
  end

  # Same id space as `answerId` (`AnswerKey`), so they never collide.
  defp gen_group_id(taken) do
    id = :rand.uniform(900_000) + 100_000
    if MapSet.member?(taken, to_string(id)), do: gen_group_id(taken), else: id
  end

  ## Walk

  defp collect(nodes, ctx, acc) when is_list(nodes) do
    acc =
      nodes
      |> Enum.with_index()
      |> Enum.reduce(acc, fn
        {%{"type" => @type_name} = node, i}, acc ->
          case group_id(node) do
            nil ->
              acc

            gid ->
              option = %{
                option_id: option_id(node),
                label: option_label(nodes, i, ctx),
                checked: checked?(node),
                verdict: Map.get(attrs(node), "verdict")
              }

              [{gid, option} | acc]
          end

        _, acc ->
          acc
      end)

    Enum.reduce(nodes, acc, &collect_node(&1, ctx, &2))
  end

  defp collect(_nodes, _ctx, acc), do: acc

  defp collect_node(%{"type" => "table", "content" => rows}, ctx, acc) when is_list(rows) do
    collect(rows, %{ctx | header: header_texts(rows)}, acc)
  end

  defp collect_node(%{"type" => "tableRow", "content" => cells}, ctx, acc) when is_list(cells) do
    cells
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {cell, col}, acc -> collect_node(cell, %{ctx | col: col}, acc) end)
  end

  defp collect_node(%{"content" => content}, ctx, acc) when is_list(content),
    do: collect(content, ctx, acc)

  defp collect_node(_node, _ctx, acc), do: acc

  # Der Text nach dem Radio, bis zum nächsten Radio im selben Elternknoten.
  defp option_label(siblings, i, ctx) do
    own =
      siblings
      |> Enum.drop(i + 1)
      |> Enum.take_while(&(Map.get(&1, "type") != @type_name))
      |> plain_text()
      |> String.trim()

    case own do
      "" -> header_label(ctx)
      text -> text
    end
  end

  defp header_label(%{header: header, col: col}) when is_list(header) and is_integer(col),
    do: header |> Enum.at(col, "") |> String.trim()

  defp header_label(_ctx), do: ""

  # Die Kopfzeile: die erste Zeile, wenn sie aus Kopfzellen besteht.
  defp header_texts([%{"type" => "tableRow", "content" => cells} | _]) when is_list(cells) do
    if cells != [] and Enum.all?(cells, &(Map.get(&1, "type") == "tableHeader")),
      do: Enum.map(cells, &plain_text([&1])),
      else: nil
  end

  defp header_texts(_rows), do: nil

  defp plain_text(nodes) when is_list(nodes) do
    Enum.map_join(nodes, "", fn
      %{"type" => "text", "text" => t} when is_binary(t) -> t
      %{"content" => inner} when is_list(inner) -> plain_text(inner)
      _ -> ""
    end)
  end

  defp attrs(node), do: Map.get(node, "attrs") || %{}

  defp string_attr(node, key) do
    case Map.get(attrs(node), key) do
      nil -> nil
      "" -> nil
      value -> to_string(value)
    end
  end
end
