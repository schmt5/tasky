defmodule Tasky.Exams.ExportRunnerTest do
  use ExUnit.Case, async: true

  alias Tasky.Exams.ExportRunner

  @exam %{name: "Geografie Prüfung"}

  defp web(render_pdf) do
    %{
      render_pdf: render_pdf,
      sign_download: fn export_id, filename -> {export_id, filename} end
    }
  end

  defp zip_entries(export_id) do
    {:ok, path} = ExportRunner.export_path(export_id)
    on_exit(fn -> File.rm(path) end)

    {:ok, entries} = :zip.unzip(String.to_charlist(path), [:memory])
    Map.new(entries, fn {name, body} -> {List.to_string(name), body} end)
  end

  test "packs one PDF per submission into a ZIP" do
    submissions = [
      %{id: 1, firstname: "Anna", lastname: "Müller"},
      %{id: 2, firstname: "Ben", lastname: "Keller"}
    ]

    {:ok, _pid} =
      ExportRunner.start(@exam, submissions, self(), web(fn sub -> {:ok, "%PDF-#{sub.id}"} end))

    assert_receive {:export_done, %{download_token: {export_id, filename}, failed: 0}}, 5_000
    assert_received {:export_progress, %{done: 0, total: 2}}
    assert filename == "Geografie-Pruefung-Export.zip"

    assert zip_entries(export_id) == %{
             "Anna-Mueller-Geografie-Pruefung.pdf" => "%PDF-1",
             "Ben-Keller-Geografie-Pruefung.pdf" => "%PDF-2"
           }
  end

  test "lists failed renders in FEHLER.txt and keeps the good PDFs" do
    submissions = [
      %{id: 1, firstname: "Anna", lastname: "Muster"},
      %{id: 2, firstname: "Ben", lastname: "Keller"},
      %{id: 3, firstname: "Cleo", lastname: "Crash"}
    ]

    render_pdf = fn
      %{id: 1} -> {:ok, "%PDF-1"}
      %{id: 2} -> {:error, "Typst kaputt"}
      %{id: 3} -> raise "boom"
    end

    {:ok, _pid} = ExportRunner.start(@exam, submissions, self(), web(render_pdf))

    assert_receive {:export_done, %{download_token: {export_id, _}, failed: 2}}, 5_000

    entries = zip_entries(export_id)
    assert Map.keys(entries) == ["Anna-Muster-Geografie-Pruefung.pdf", "FEHLER.txt"]
    assert entries["FEHLER.txt"] =~ "Ben Keller"
    assert entries["FEHLER.txt"] =~ "Cleo Crash"
  end

  test "fails outright when no PDF could be rendered" do
    submissions = [%{id: 1, firstname: "Anna", lastname: "Muster"}]

    {:ok, _pid} =
      ExportRunner.start(@exam, submissions, self(), web(fn _ -> {:error, "kaputt"} end))

    assert_receive {:export_failed, {:render_error, "kaputt"}}, 5_000
  end

  test "refuses an empty submission list" do
    assert {:error, :no_submissions} = ExportRunner.start(@exam, [], self(), web(& &1))
  end
end
