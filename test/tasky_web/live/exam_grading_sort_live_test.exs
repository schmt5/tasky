defmodule TaskyWeb.ExamGradingSortLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  # First and last names deliberately run against each other: by first name the
  # order is Anna/Bruno/Carla, by last name Ammann/Meier/Zimmermann.
  @people [
    {"Anna", "Zimmermann"},
    {"Bruno", "Ammann"},
    {"Carla", "Meier"}
  ]

  defp graded_exam do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    exam = exam_fixture(scope: scope, status: "running")
    {:ok, exam, _} = Exams.set_mark_step(scope, exam, "0.25")

    submissions =
      for {firstname, lastname} <- @people do
        exam_submission_fixture(exam, %{
          "firstname" => firstname,
          "lastname" => lastname,
          "email" => "#{String.downcase(lastname)}@example.com"
        })
      end

    {:ok, exam} = Exams.update_exam_status(scope, exam, "finished")

    %{teacher: teacher, scope: scope, exam: exam, submissions: submissions}
  end

  defp open(conn, teacher, path) do
    conn |> log_in_user(teacher) |> live(path)
  end

  # Reads one table column in display order. The name cell also carries the
  # avatar's initials, so the span — not the whole cell — is what is read.
  defp column(html, nth) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("tbody tr td:nth-child(#{nth}) span")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  defp firstnames(html), do: column(html, 1)
  defp lastnames(html), do: column(html, 2)

  test "first and last name sit in separate cells", %{conn: conn} do
    %{teacher: teacher, exam: exam} = graded_exam()

    {:ok, _view, html} = open(conn, teacher, ~p"/exams/#{exam}/correction/grading")

    assert firstnames(html) == ["Anna", "Bruno", "Carla"]
    assert lastnames(html) == ["Zimmermann", "Ammann", "Meier"]
  end

  test "without params the table is sorted by first name ascending", %{conn: conn} do
    %{teacher: teacher, exam: exam} = graded_exam()

    {:ok, _view, html} = open(conn, teacher, ~p"/exams/#{exam}/correction/grading")

    assert firstnames(html) == ["Anna", "Bruno", "Carla"]
  end

  test "sort=lastname orders by last name and dir=desc reverses it", %{conn: conn} do
    %{teacher: teacher, exam: exam} = graded_exam()

    {:ok, _view, html} =
      open(conn, teacher, ~p"/exams/#{exam}/correction/grading?sort=lastname&dir=asc")

    assert lastnames(html) == ["Ammann", "Meier", "Zimmermann"]

    {:ok, _view, html} =
      open(conn, teacher, ~p"/exams/#{exam}/correction/grading?sort=lastname&dir=desc")

    assert lastnames(html) == ["Zimmermann", "Meier", "Ammann"]
  end

  test "clicking the active column flips the direction", %{conn: conn} do
    %{teacher: teacher, exam: exam} = graded_exam()

    {:ok, view, _html} = open(conn, teacher, ~p"/exams/#{exam}/correction/grading")

    html = view |> element("#sort-lastname") |> render_click()
    assert lastnames(html) == ["Ammann", "Meier", "Zimmermann"]

    html = view |> element("#sort-lastname") |> render_click()
    assert lastnames(html) == ["Zimmermann", "Meier", "Ammann"]

    # Another column starts ascending again.
    html = view |> element("#sort-firstname") |> render_click()
    assert firstnames(html) == ["Anna", "Bruno", "Carla"]
  end

  test "unknown params fall back to first name ascending", %{conn: conn} do
    %{teacher: teacher, exam: exam} = graded_exam()

    {:ok, _view, html} =
      open(conn, teacher, ~p"/exams/#{exam}/correction/grading?sort=bobby&dir=tables")

    assert firstnames(html) == ["Anna", "Bruno", "Carla"]
  end

  test "participants without a mark sort last in both directions", %{conn: conn} do
    %{teacher: teacher, scope: scope, exam: exam, submissions: submissions} = graded_exam()

    # Only two of the three get a mark — the third stays without one.
    [zimmermann, ammann, _meier] = submissions
    {:ok, _} = Exams.set_submission_mark(scope, zimmermann, 4.0)
    {:ok, _} = Exams.set_submission_mark(scope, ammann, 5.5)

    {:ok, _view, html} =
      open(conn, teacher, ~p"/exams/#{exam}/correction/grading?sort=mark&dir=asc")

    assert lastnames(html) == ["Zimmermann", "Ammann", "Meier"]

    {:ok, _view, html} =
      open(conn, teacher, ~p"/exams/#{exam}/correction/grading?sort=mark&dir=desc")

    assert lastnames(html) == ["Ammann", "Zimmermann", "Meier"]
  end

  test "saving a mark does not make the row jump", %{conn: conn} do
    %{teacher: teacher, exam: exam, submissions: submissions} = graded_exam()
    [_zimmermann, ammann, _meier] = submissions

    {:ok, view, _html} =
      open(conn, teacher, ~p"/exams/#{exam}/correction/grading?sort=lastname&dir=asc")

    assert lastnames(render(view)) == ["Ammann", "Meier", "Zimmermann"]

    # Re-sorting happens only on a header click — otherwise the row would slip
    # out from under the cursor while a mark is being typed.
    html = render_change(view, "set_mark", %{"submission_id" => ammann.id, "mark" => "6"})

    assert lastnames(html) == ["Ammann", "Meier", "Zimmermann"]
  end
end
