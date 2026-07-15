defmodule TaskyWeb.FileComponents do
  @moduledoc """
  Shared UI helpers for exam attachments and file submissions: type badges,
  type-chip labels and upload error messages (German).
  """
  use Phoenix.Component

  alias Tasky.Uploads

  @doc """
  Colored square badge showing a file's type, derived from the stored
  filename's extension (e.g. red "PDF", amber "MP3").
  """
  attr :filename, :string, required: true
  attr :size, :string, default: "md", values: ~w(sm md)

  def file_badge(assigns) do
    ext = assigns.filename |> Path.extname() |> String.downcase()
    type_key = Uploads.type_key_for_ext(ext)

    assigns =
      assigns
      |> assign(:text, ext |> String.trim_leading(".") |> String.upcase())
      |> assign(:color, badge_color(type_key))

    ~H"""
    <span class={[
      "inline-flex items-center justify-center text-white font-bold tracking-wide shrink-0",
      if(@size == "sm",
        do: "px-1.5 py-0.5 rounded text-[9px]",
        else: "w-12 h-12 rounded-xl text-[11px]"
      ),
      @color
    ]}>
      {@text}
    </span>
    """
  end

  defp badge_color("pdf"), do: "bg-red-500"
  defp badge_color("docx"), do: "bg-blue-600"
  defp badge_color("xlsx"), do: "bg-emerald-600"
  defp badge_color("pptx"), do: "bg-orange-500"
  defp badge_color("image"), do: "bg-violet-500"
  defp badge_color("audio"), do: "bg-amber-600"
  defp badge_color("zip"), do: "bg-stone-500"
  defp badge_color(_), do: "bg-stone-400"

  @doc "Display label for a file-type chip (registry type key)."
  def type_chip_label("image"), do: "JPG / PNG"
  def type_chip_label("audio"), do: "MP3 / M4A"

  def type_chip_label(type) do
    case Uploads.file_type(type) do
      %{badge: badge} -> badge
      nil -> String.upcase(type)
    end
  end

  @doc "Human-readable type label for a stored filename."
  def file_type_label(filename) do
    type_key = filename |> Path.extname() |> Uploads.type_key_for_ext()

    case Uploads.file_type(type_key) do
      %{label: label} -> label
      _ -> "Datei"
    end
  end

  @doc "German message for a LiveView upload error atom."
  def upload_error_message(:too_large), do: "Datei ist zu gross (max. 25 MB)."
  def upload_error_message(:not_accepted), do: "Dieser Dateityp ist nicht erlaubt."
  def upload_error_message(:too_many_files), do: "Zu viele Dateien auf einmal."
  def upload_error_message(_), do: "Upload fehlgeschlagen."
end
