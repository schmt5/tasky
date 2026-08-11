defmodule Tasky.UploadsTest do
  use ExUnit.Case, async: true

  alias Tasky.Uploads

  setup do
    dir = Path.join(System.tmp_dir!(), "tasky_uploads_test_#{System.unique_integer([:positive])}")
    prev = Application.get_env(:tasky, :uploads_dir)
    Application.put_env(:tasky, :uploads_dir, dir)

    on_exit(fn ->
      File.rm_rf(dir)
      if prev, do: Application.put_env(:tasky, :uploads_dir, prev)
    end)

    :ok
  end

  defp tmp_file(content) do
    path = Path.join(System.tmp_dir!(), "upload_src_#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  defp upload(content, content_type) do
    %Plug.Upload{path: tmp_file(content), content_type: content_type, filename: "x"}
  end

  @png_bytes <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "fake-image-data">>
  @jpg_bytes <<0xFF, 0xD8, 0xFF, 0xE0, "fake-image-data">>

  describe "save_exam_image/2" do
    test "stores a valid png and returns a fetchable public url" do
      assert {:ok, url} = Uploads.save_exam_image("42", upload(@png_bytes, "image/png"))
      assert url =~ ~r"^/uploads/exams/42/[0-9a-f-]+\.png$"

      filename = url |> String.split("/") |> List.last()
      assert {:ok, {{:file, path}, "image/png"}} = Uploads.fetch_exam_image("42", filename)
      assert File.exists?(path)
    end

    test "maps jpeg content type to a .jpg extension" do
      assert {:ok, url} = Uploads.save_exam_image("1", upload(@jpg_bytes, "image/jpeg"))
      assert String.ends_with?(url, ".jpg")
    end

    test "rejects an unsupported content type" do
      assert {:error, :unsupported_type} =
               Uploads.save_exam_image("1", upload("bytes", "application/pdf"))
    end

    test "rejects files over the 10 MB limit" do
      big = @png_bytes <> :binary.copy("a", 10 * 1024 * 1024 + 1)
      assert {:error, :too_large} = Uploads.save_exam_image("1", upload(big, "image/png"))
    end

    test "rejects content whose bytes don't match the claimed image type" do
      html = "<html><script>alert(1)</script></html>"
      assert {:error, :invalid_image} = Uploads.save_exam_image("1", upload(html, "image/png"))

      # png bytes uploaded as jpeg are also a mismatch
      assert {:error, :invalid_image} =
               Uploads.save_exam_image("1", upload(@png_bytes, "image/jpeg"))
    end

    test "accepts gif and webp signatures" do
      gif = "GIF89a" <> <<0, 0, 0, 0>>
      webp = "RIFF" <> <<0, 0, 0, 0>> <> "WEBP" <> "VP8 "

      assert {:ok, _} = Uploads.save_exam_image("1", upload(gif, "image/gif"))
      assert {:ok, _} = Uploads.save_exam_image("1", upload(webp, "image/webp"))
    end
  end

  describe "fetch_exam_image/2" do
    test "rejects path traversal in the filename" do
      assert {:error, :invalid} = Uploads.fetch_exam_image("1", "../../secret.png")
    end

    test "rejects an unknown extension" do
      assert {:error, _} = Uploads.fetch_exam_image("1", "evil.exe")
    end

    test "returns not_found for a missing file" do
      assert {:error, :not_found} =
               Uploads.fetch_exam_image("1", "#{Ecto.UUID.generate()}.png")
    end
  end

  describe "Musterlösungs-Dateien" do
    test "stores, fetches and deletes a docx" do
      assert {:ok, meta} =
               Uploads.save_task_solution_file("42", tmp_file("bytes"), "loesung.docx")

      assert meta.stored_filename =~ ~r/^[0-9a-f-]+\.docx$/
      assert meta.size == byte_size("bytes")

      assert {:ok, {:file, path}} =
               Uploads.fetch_task_solution_file("42", meta.stored_filename)

      assert File.exists?(path)

      Uploads.delete_task_solution_file("42", meta.stored_filename)

      assert {:error, :not_found} =
               Uploads.fetch_task_solution_file("42", meta.stored_filename)
    end

    test "rejects an extension outside the attachment whitelist" do
      assert {:error, _} = Uploads.save_task_solution_file("42", tmp_file("x"), "boese.exe")
    end

    test "rejects path traversal on fetch" do
      assert {:error, :invalid} = Uploads.fetch_task_solution_file("42", "../../secret.docx")
    end

    # Der Prefix liegt unter tasks/<id>, damit das Löschen der Lerneinheit die
    # Bytes mitnimmt — sonst leckt jede gelöschte Einheit ihre Lösungsdateien.
    test "delete_task_files/1 clears the solution prefix too" do
      {:ok, meta} = Uploads.save_task_solution_file("77", tmp_file("bytes"), "loesung.docx")
      assert {:ok, _} = Uploads.fetch_task_solution_file("77", meta.stored_filename)

      Uploads.delete_task_files("77")

      assert {:error, :not_found} =
               Uploads.fetch_task_solution_file("77", meta.stored_filename)
    end

    test "plan_solution_file_copy/3 mints a fresh stored filename" do
      assert {:ok, new_name, job} =
               Uploads.plan_solution_file_copy("1", "2", "abc.docx")

      assert new_name =~ ~r/^[0-9a-f-]+\.docx$/
      assert new_name != "abc.docx"
      assert job.src == "tasks/1/solution/abc.docx"
      assert job.dest == "tasks/2/solution/#{new_name}"
    end

    test "plan_solution_file_copy/3 refuses an unsafe filename" do
      assert {:error, :invalid} =
               Uploads.plan_solution_file_copy("1", "2", "../../secret.docx")
    end
  end
end
