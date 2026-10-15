defmodule Tasky.PDF do
  @moduledoc """
  Renders PDFs with Typst (the `typst` NIF) — in-process, synchronous, no
  external service.

  The Tiptap documents are **data, not markup**: `render/2` encodes everything
  into a `data.json` in Typst's virtual file system, and the templates under
  `priv/typst/` read it with `json(...)` and walk the nodes themselves
  (`priv/typst/tiptap.typ`). A string from a document therefore reaches Typst
  as text and is never parsed as markup — no escaping, no injection via `#`,
  `$` or `]`. The markup string passed to the NIF is a constant and must stay
  one: it runs through EEx.

  This is the only server-side renderer of Tiptap documents for humans; the
  web views still render client-side with the React editor. A node type the
  templates do not know renders its children, so a new editor extension
  degrades instead of breaking the export — but it should be added to
  `tiptap.typ` alongside `ExamContentEditor.jsx`.
  """

  require Logger

  @templates ~w(paper submission)

  # Typst caps its call depth (80), and the templates spend up to five calls
  # per document level. Content nested deeper than this is flattened to its
  # text rather than failing the whole PDF.
  @max_depth 12

  @hex_color ~r/\A#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\z/

  @doc """
  Renders `priv/typst/<template>.typ` with `data` (a JSON-encodable map) and
  returns `{:ok, pdf_binary}` or `{:error, message}`.

  Images referenced by documents inside `data` are loaded (see `prepare/2`)
  and handed to Typst as assets.

  Options:

    * `:read_image` — passed to `prepare/2`
  """
  @spec render(String.t(), map(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def render(template, data, opts \\ []) when template in @templates and is_map(data) do
    {data, images} =
      prepare(data, Keyword.get(opts, :read_image, &Tasky.Uploads.read_content_image/1))

    markup = ~s|#import "/#{template}.typ": render\n#render(json("/data.json"))\n|

    case Typst.render_to_pdf(markup, [],
           root_dir: typst_dir(),
           extra_fonts: [Path.join(typst_dir(), "fonts")],
           assets: [{"data.json", Jason.encode!(data)} | images]
         ) do
      {:ok, pdf} ->
        {:ok, pdf}

      {:error, message} ->
        Logger.error("Typst-Rendering (#{template}) fehlgeschlagen: #{message}")
        {:error, message}
    end
  end

  @doc """
  Prepares data for the templates: every `image` node's `src` is replaced by
  a virtual asset path (`/img/<n><ext>`), and the image bytes are returned as
  assets. An image that cannot be loaded — an external URL, a deleted file —
  gets `src: nil`, which the template renders as a placeholder. Colours that
  are not plain hex values are dropped, because an invalid `rgb(...)` aborts
  the whole Typst run. Content nested deeper than #{@max_depth} levels is
  flattened into one paragraph of its text.

  `read_image` defaults to `Tasky.Uploads.read_content_image/1`.
  """
  @spec prepare(term(), (String.t() -> {:ok, {binary(), String.t()}} | {:error, term()})) ::
          {term(), [{String.t(), binary()}]}
  def prepare(data, read_image \\ &Tasky.Uploads.read_content_image/1) do
    {data, %{assets: assets}} =
      data
      |> limit_depth(0)
      |> walk(%{paths: %{}, assets: [], read: read_image})

    {data, Enum.reverse(assets)}
  end

  defp walk(%{"type" => "image", "attrs" => %{} = attrs} = node, acc) do
    {path, acc} = image_path(Map.get(attrs, "src"), acc)
    {%{node | "attrs" => Map.put(attrs, "src", path)}, acc}
  end

  defp walk(%{"type" => type, "attrs" => %{"color" => color} = attrs} = node, acc)
       when type in ["textStyle", "highlight"] do
    walk_map(%{node | "attrs" => Map.put(attrs, "color", hex_color(color))}, acc)
  end

  defp walk(map, acc) when is_map(map), do: walk_map(map, acc)

  defp walk(list, acc) when is_list(list), do: Enum.map_reduce(list, acc, &walk/2)

  defp walk(other, acc), do: {other, acc}

  defp walk_map(map, acc) do
    {pairs, acc} =
      Enum.map_reduce(map, acc, fn {key, value}, acc ->
        {value, acc} = walk(value, acc)
        {{key, value}, acc}
      end)

    {Map.new(pairs), acc}
  end

  # Depth counts document nodes (maps with a type and a content list) only, so
  # the wrapping data and the marks on a text node do not use up the budget.
  defp limit_depth(%{"type" => _, "content" => content} = node, depth)
       when is_list(content) and depth >= @max_depth do
    %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => plain_text(node)}]}
  end

  defp limit_depth(%{"type" => _, "content" => content} = node, depth) when is_list(content) do
    %{node | "content" => Enum.map(content, &limit_depth(&1, depth + 1))}
  end

  defp limit_depth(map, depth) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, limit_depth(value, depth)} end)

  defp limit_depth(list, depth) when is_list(list), do: Enum.map(list, &limit_depth(&1, depth))

  defp limit_depth(other, _depth), do: other

  defp plain_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text

  defp plain_text(%{"content" => content}) when is_list(content) do
    content |> Enum.map(&plain_text/1) |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
  end

  defp plain_text(_node), do: ""

  # The same image used twice is loaded and embedded once.
  defp image_path(src, %{paths: paths} = acc) when is_binary(src) and src != "" do
    case Map.fetch(paths, src) do
      {:ok, path} ->
        {path, acc}

      :error ->
        {path, acc} = load_image(src, acc)
        {path, %{acc | paths: Map.put(acc.paths, src, path)}}
    end
  end

  defp image_path(_src, acc), do: {nil, acc}

  defp load_image(src, acc) do
    case acc.read.(src) do
      {:ok, {bytes, ext}} ->
        path = "/img/#{map_size(acc.paths)}#{ext}"
        {path, %{acc | assets: [{String.trim_leading(path, "/"), bytes} | acc.assets]}}

      {:error, reason} ->
        Logger.warning("PDF: Bild #{inspect(src)} nicht ladbar: #{inspect(reason)}")
        {nil, acc}
    end
  end

  defp hex_color(color) when is_binary(color) do
    if Regex.match?(@hex_color, color), do: color, else: nil
  end

  defp hex_color(_color), do: nil

  defp typst_dir, do: Application.app_dir(:tasky, "priv/typst")
end
