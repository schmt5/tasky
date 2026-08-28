defmodule TaskyWeb.Plugs.SebGuardTest do
  @moduledoc """
  The hole this closes: before the guard existed, the only SEB check was
  `String.contains?(user_agent, "SEB")`, and it gated nothing but the rendered
  page. Setting one string in a user-agent switcher took the whole exam in a
  normal browser with the internet open — and the cockpit showed that
  participant as a green shield.
  """
  use TaskyWeb.ConnCase, async: false

  import Tasky.ExamsFixtures

  alias Tasky.Exams
  alias Tasky.Exams.SebConfig
  alias TaskyWeb.SebGuard

  @seb_ua "Mozilla/5.0 (Windows NT 10.0) SEB/3.5.0"

  defp seb_exam(enforcement) do
    exam = exam_fixture(status: "running")

    {:ok, exam} =
      exam
      |> Ecto.Changeset.change(%{
        seb_enabled: true,
        seb_quit_password: "PRZN-9XXN-79Z",
        seb_admin_password: "SSMW6X9PVV54GAN8SDNLLNE69D"
      })
      |> Tasky.Repo.update()

    {:ok, exam} = Exams.set_seb_enforcement(:system, exam, enforcement)
    {:ok, submission} = Exams.create_exam_submission(exam, valid_enrollment_attrs())

    {exam, Tasky.Repo.preload(submission, :exam, force: true)}
  end

  defp valid_hash(exam, submission) do
    exam |> SebGuard.config_opts(submission) |> SebConfig.config_key()
  end

  defp with_hash(conn, hash),
    do: put_req_header(conn, SebGuard.header_name(), hash)

  describe "enforce mode" do
    test "refuses a request with no SEB header", %{conn: conn} do
      {_exam, submission} = seb_exam("enforce")

      conn = get(conn, ~p"/guest/exam/#{submission.exam_token}")

      assert conn.status == 403
      assert html_response(conn, 403) =~ "Safe Exam Browser erforderlich"
    end

    test "refuses a spoofed user agent with no header", %{conn: conn} do
      # THE regression test. This exact request used to render the whole exam.
      {_exam, submission} = seb_exam("enforce")

      conn =
        conn
        |> put_req_header("user-agent", @seb_ua)
        |> get(~p"/guest/exam/#{submission.exam_token}")

      assert conn.status == 403
    end

    test "refuses a header carrying the wrong hash, and says so", %{conn: conn} do
      {_exam, submission} = seb_exam("enforce")

      conn =
        conn
        |> with_hash(String.duplicate("a", 64))
        |> get(~p"/guest/exam/#{submission.exam_token}")

      body = html_response(conn, 403)
      assert body =~ "andere Konfiguration"
    end

    test "admits a valid hash and stamps the session", %{conn: conn} do
      {exam, submission} = seb_exam("enforce")

      conn =
        conn
        |> with_hash(valid_hash(exam, submission))
        |> get(~p"/guest/exam/#{submission.exam_token}")

      assert conn.status == 200
      # The stamp is what carries the verification onto the websocket, where
      # SEB may not repeat the header.
      assert %{"token" => token} = get_session(conn, "seb")
      assert token == submission.exam_token
    end

    test "accepts a hash the teacher explicitly blessed", %{conn: conn} do
      # The operator override: an exam-day escape from a derivation that is
      # subtly wrong for one SEB build.
      {exam, submission} = seb_exam("enforce")
      observed = String.duplicate("b", 64)
      {:ok, _exam} = Exams.accept_seb_config_key(:system, exam, observed)

      conn =
        conn
        |> with_hash(observed)
        |> get(~p"/guest/exam/#{submission.exam_token}")

      assert conn.status == 200
    end

    test "the kill switch degrades enforce to observe", %{conn: conn} do
      {exam, submission} = seb_exam("enforce")
      {:ok, _exam} = Exams.bypass_seb(:system, exam, 15)

      conn = get(conn, ~p"/guest/exam/#{submission.exam_token}")

      assert conn.status == 200
    end

    test "an expired kill switch enforces again", %{conn: conn} do
      {exam, submission} = seb_exam("enforce")

      {:ok, _exam} =
        exam
        |> Ecto.Changeset.change(%{
          seb_bypass_until: DateTime.utc_now() |> DateTime.add(-60) |> DateTime.truncate(:second)
        })
        |> Tasky.Repo.update()

      conn = get(conn, ~p"/guest/exam/#{submission.exam_token}")

      assert conn.status == 403
    end
  end

  describe "observe and off modes" do
    test "observe never blocks, even with no header at all", %{conn: conn} do
      # The whole point of having a stage before enforce: the Config Key
      # derivation must be confirmed against a real SEB before it can lock
      # anyone out.
      {_exam, submission} = seb_exam("observe")

      assert conn |> get(~p"/guest/exam/#{submission.exam_token}") |> Map.get(:status) == 200
    end

    test "off never blocks", %{conn: conn} do
      {_exam, submission} = seb_exam("off")

      assert conn |> get(~p"/guest/exam/#{submission.exam_token}") |> Map.get(:status) == 200
    end

    test "an exam without SEB enabled is never guarded", %{conn: conn} do
      exam = exam_fixture(status: "running")
      {:ok, exam} = Exams.set_seb_enforcement(:system, exam, "enforce")
      {:ok, submission} = Exams.create_exam_submission(exam, valid_enrollment_attrs())

      assert conn |> get(~p"/guest/exam/#{submission.exam_token}") |> Map.get(:status) == 200
    end
  end

  describe "the way into SEB stays open" do
    test "the config download is reachable without a header", %{conn: conn} do
      {_exam, submission} = seb_exam("enforce")

      conn = get(conn, ~p"/guest/exam/#{submission.exam_token}/seb-config")

      assert conn.status == 200
      assert ["attachment; filename=\"exam.seb\""] = get_resp_header(conn, "content-disposition")
    end

    test "the quit page is reachable without a header", %{conn: conn} do
      # It has to work while SEB is shutting down.
      {_exam, submission} = seb_exam("enforce")

      assert conn
             |> get(~p"/guest/exam/#{submission.exam_token}/seb-quit")
             |> Map.get(:status) == 200
    end

    test "the gate page is reachable without a header", %{conn: conn} do
      {_exam, submission} = seb_exam("enforce")

      conn = get(conn, ~p"/guest/exam/#{submission.exam_token}/seb-required")

      assert html_response(conn, 403) =~ "Safe Exam Browser erforderlich"
    end
  end

  describe "the JSON autosave API" do
    test "refuses without a header, with the code the client needs", %{conn: conn} do
      # `assets/js/react/api.js` turns a bare 403 into a permanent "Sitzung
      # abgelaufen" and stops autosaving. The `code` is what lets it say what
      # actually happened instead.
      {_exam, submission} = seb_exam("enforce")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/guest/exam/#{submission.exam_token}/content", %{
          "content" => %{"type" => "doc"}
        })

      assert conn.status == 403
      assert %{"code" => "seb_required"} = Jason.decode!(conn.resp_body)
    end

    test "admits a valid hash", %{conn: conn} do
      {exam, submission} = seb_exam("enforce")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> with_hash(valid_hash(exam, submission))
        |> put(~p"/api/guest/exam/#{submission.exam_token}/content", %{
          "content" => %{"type" => "doc", "content" => []}
        })

      assert conn.status == 200
    end
  end
end
