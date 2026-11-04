defmodule Tasky.Correction.ImagePin do
  @moduledoc """
  Pin auf Bild: ein `imagePin`-Knoten ist ein Bild, auf das Lernende
  nummerierte Pins setzen.

  Alles an den Pins steht in einer Liste `attrs["pins"]`, deren Einträge je
  nach Dokument mehr oder weniger tragen:

    * **Musterlösung** (`exam.sample_solution[answerId]`, das Autoren-Dokument):
      `%{"pinId", "x", "y", "zone"}` — wo der Pin hingehört und wie weit
      daneben noch zählt. `zone` ist `%{"shape" => "circle", "r" => r}` oder
      `%{"shape" => "rect", "w" => w, "h" => h}`.
    * **Aufgabe** (`exam.content`, was Lernende bekommen): nur `%{"pinId"}`.
      Lernende erfahren, wie viele Pins es gibt, aber nicht wo. Diese Liste ist
      der einzige Weg dahin: `Tasky.Exams.learner_exam/1` hält die
      Musterlösung aus der Lernendenansicht heraus.
    * **Antwort** (`submission.content`): `%{"pinId", "x", "y"}`, `x`/`y`
      `nil` für einen Pin, den die lernende Person nicht gesetzt hat.

  Koordinaten sind relativ zum Bild (`0..1` von links oben), damit sie bei
  jeder Bildschirmgrösse gelten. Der Kreisradius `r` ist relativ zur
  Bildbreite; damit ein Kreis auch auf einem breiten Bild rund bleibt, rechnet
  `hit?/3` die Höhe über das Seitenverhältnis `attrs["aspect"]` (Breite/Höhe)
  in Breiten-Einheiten um. Ein Rechteck ist achsenparallel, `w`/`h` sind
  relativ zu Breite und Höhe, `x`/`y` sein Mittelpunkt.

  Nummer und Farbe eines Pins ergeben sich aus seiner Stelle in der Liste
  (`colors/0`) — die Lehrperson wählt sie nicht, Lernende sehen nur sie.

  Bewertet wird das Bild als ein Antwortblock: alle Pins getroffen ergibt
  `"correct"`, keiner `"wrong"`, dazwischen die Punkte anteilig
  (`verdict/4`).
  """

  @max_pins 8

  # Okabe-Ito: auch bei Farbenblindheit unterscheidbar. Dieselbe Liste steht
  # in `assets/js/image_pin_colors.js` und `priv/typst/tiptap.typ`.
  @colors ~w(#E69F00 #56B4E9 #009E73 #F0E442 #0072B2 #D55E00 #CC79A7 #1C1917)
  # The colour of the number on each, for contrast.
  @number_colors ~w(#1C1917 #1C1917 #FFFFFF #1C1917 #FFFFFF #FFFFFF #1C1917 #FFFFFF)

  @default_zone %{"shape" => "circle", "r" => 0.05}

  def max_pins, do: @max_pins
  def colors, do: @colors

  @doc "`{background, number}` colour of the pin at `index` (0-based)."
  def color(index) when is_integer(index) and index >= 0 do
    i = rem(index, length(@colors))
    {Enum.at(@colors, i), Enum.at(@number_colors, i)}
  end

  @doc "The pin list of a node, or `[]`."
  def pins(node) do
    case get_in(node, ["attrs", "pins"]) do
      pins when is_list(pins) -> Enum.filter(pins, &is_binary(pin_id(&1)))
      _ -> []
    end
  end

  @doc "The image's width/height, `1.0` when unknown."
  def aspect(node) do
    case get_in(node, ["attrs", "aspect"]) do
      aspect when is_number(aspect) and aspect > 0 -> aspect / 1
      _ -> 1.0
    end
  end

  def pin_id(%{"pinId" => id}) when is_binary(id) and id != "", do: id
  def pin_id(_pin), do: nil

  @doc "Only the ids: what learners may know of the sample solution."
  def public_pins(pins) when is_list(pins) do
    for pin <- pins, id = pin_id(pin), do: %{"pinId" => id}
  end

  def public_pins(_pins), do: []

  @doc """
  The teacher's pins, cut back to what a sample solution holds: known keys,
  coordinates and sizes inside the image, at most #{@max_pins} pins, no
  duplicate ids. A pin without a position keeps none (the teacher has not
  placed it yet) — it then counts as missed.
  """
  def solution_pins(pins) when is_list(pins) do
    pins
    |> Enum.filter(&is_binary(pin_id(&1)))
    |> Enum.uniq_by(&pin_id/1)
    |> Enum.take(@max_pins)
    |> Enum.map(fn pin ->
      %{"pinId" => pin_id(pin), "zone" => zone(pin["zone"])}
      |> Map.merge(position(pin))
    end)
  end

  def solution_pins(_pins), do: []

  @doc """
  A learner's answer, against the pin ids the exam gave them: one entry per
  known id, in their order; a missing or unplaceable pin has `x`/`y` `nil`.
  `:ignore` for anything that is not a list.
  """
  def learner_pins(pin_ids, value) when is_list(pin_ids) and is_list(value) do
    given =
      value
      |> Enum.filter(&is_map/1)
      |> Enum.reduce(%{}, fn pin, acc -> Map.put_new(acc, pin_id(pin), pin) end)

    Enum.map(pin_ids, fn id ->
      Map.merge(%{"pinId" => id, "x" => nil, "y" => nil}, position(Map.get(given, id, %{})))
    end)
  end

  def learner_pins(_pin_ids, _value), do: :ignore

  @doc "Whether a learner's pin lies in the zone of the sample's pin."
  def hit?(%{"x" => x, "y" => y}, %{"x" => sx, "y" => sy, "zone" => zone}, aspect)
      when is_number(x) and is_number(y) and is_number(sx) and is_number(sy) do
    inside?(zone(zone), x - sx, y - sy, aspect)
  end

  def hit?(_answer, _sample, _aspect), do: false

  @doc """
  `{hits, total}` of a learner's pins against the sample's, paired by id.
  """
  def score(answer_pins, sample_pins, aspect) do
    sample_pins = Enum.filter(List.wrap(sample_pins), &is_binary(pin_id(&1)))
    answers = answer_pins |> List.wrap() |> Map.new(&{pin_id(&1), &1})

    hits = Enum.count(sample_pins, &hit?(Map.get(answers, pin_id(&1)), &1, aspect))
    {hits, length(sample_pins)}
  end

  @doc """
  The block verdict for `{hits, total}`, with `block_max` the image's points:
  `"correct"` for all, `"wrong"` for none, else the share of the points as a
  number (a manual-points verdict, `Tasky.Grading`). Without points to share,
  anything short of all is `"wrong"`. `nil` for a sample without pins —
  nothing to compare against.
  """
  def verdict({_hits, 0}, _block_max), do: nil
  def verdict({total, total}, _block_max), do: "correct"
  def verdict({0, _total}, _block_max), do: "wrong"

  def verdict({hits, total}, block_max) when is_number(block_max) and block_max > 0,
    do: Tasky.Grading.round_quarter(block_max * hits / total)

  def verdict(_score, _block_max), do: "wrong"

  @doc """
  Sets every `imagePin`'s public pin list from the sample solution — the
  authority on how many pins there are. Run on each save of the exam's
  structure: an "Inhalt" editor opened before the teacher placed pins in the
  "Musterlösung" would otherwise save its stale, pin-less copy over it.
  """
  def sync_public_pins(%{"content" => content} = doc, sample) when is_list(content) do
    synced =
      map_pin_nodes(content, fn node ->
        put_attr(
          node,
          "pins",
          sample |> Kernel.||(%{}) |> Map.get(answer_key(node)) |> public_pins()
        )
      end)

    Map.put(doc, "content", synced)
  end

  def sync_public_pins(doc, _sample), do: doc

  @doc """
  Hangs the sample's pins onto every `imagePin` in `nodes` as
  `attrs["solution"]`, for the teacher's correction views to draw the zones.
  Never stored: `without_solution/1` takes it off again on the way back.
  """
  def with_solution(nodes, sample) when is_list(nodes) do
    map_pin_nodes(nodes, fn node ->
      case Map.get(sample || %{}, answer_key(node)) do
        [_ | _] = pins -> put_attr(node, "solution", pins)
        _ -> node
      end
    end)
  end

  @doc "Takes `attrs[\"solution\"]` off every `imagePin` in `nodes`."
  def without_solution(nodes) when is_list(nodes) do
    map_pin_nodes(nodes, fn node ->
      Map.update(node, "attrs", %{}, &Map.delete(&1, "solution"))
    end)
  end

  defp map_pin_nodes(nodes, fun) do
    Enum.map(nodes, fn
      %{"type" => "imagePin"} = node ->
        fun.(node)

      %{"content" => content} = node when is_list(content) ->
        Map.put(node, "content", map_pin_nodes(content, fun))

      node ->
        node
    end)
  end

  defp answer_key(node), do: node |> get_in(["attrs", "answerId"]) |> then(&(&1 && to_string(&1)))

  defp put_attr(node, key, value),
    do: Map.put(node, "attrs", node |> Map.get("attrs", %{}) |> Map.put(key, value))

  # --- Geometrie --------------------------------------------------------------

  # The edge counts as inside — give or take float noise (0.55 - 0.5 is a
  # hair over 0.05).
  @epsilon 1.0e-9

  defp inside?(%{"shape" => "rect", "w" => w, "h" => h}, dx, dy, _aspect),
    do: abs(dx) <= w / 2 + @epsilon and abs(dy) <= h / 2 + @epsilon

  defp inside?(%{"shape" => "circle", "r" => r}, dx, dy, aspect) do
    dy = dy / aspect
    :math.sqrt(dx * dx + dy * dy) <= r + @epsilon
  end

  defp zone(%{"shape" => "rect", "w" => w, "h" => h}) when is_number(w) and is_number(h),
    do: %{"shape" => "rect", "w" => size(w), "h" => size(h)}

  defp zone(%{"shape" => "circle", "r" => r}) when is_number(r),
    do: %{"shape" => "circle", "r" => size(r)}

  defp zone(_zone), do: @default_zone

  defp position(%{"x" => x, "y" => y}) when is_number(x) and is_number(y),
    do: %{"x" => unit(x), "y" => unit(y)}

  defp position(_pin), do: %{}

  defp unit(n), do: n |> max(0) |> min(1) |> Kernel./(1) |> Float.round(4)
  defp size(n), do: n |> max(0.005) |> min(1) |> Kernel./(1) |> Float.round(4)
end
