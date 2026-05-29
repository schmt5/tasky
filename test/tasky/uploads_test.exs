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

  describe "save_exam_image/2" do
    test "stores a valid png and returns a fetchable public url" do
      assert {:ok, url} = Uploads.save_exam_image("42", upload("png-bytes", "image/png"))
      assert url =~ ~r"^/uploads/exams/42/[0-9a-f-]+\.png$"

      filename = url |> String.split("/") |> List.last()
      assert {:ok, {path, "image/png"}} = Uploads.fetch_exam_image("42", filename)
      assert File.exists?(path)
    end

    test "maps jpeg content type to a .jpg extension" do
      assert {:ok, url} = Uploads.save_exam_image("1", upload("bytes", "image/jpeg"))
      assert String.ends_with?(url, ".jpg")
    end

    test "rejects an unsupported content type" do
      assert {:error, :unsupported_type} =
               Uploads.save_exam_image("1", upload("bytes", "application/pdf"))
    end

    test "rejects files over the 10 MB limit" do
      big = :binary.copy("a", 10 * 1024 * 1024 + 1)
      assert {:error, :too_large} = Uploads.save_exam_image("1", upload(big, "image/png"))
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
end
