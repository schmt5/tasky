defmodule TaskyWeb.ExamCorrectionBulkNavLiveTest do
  @moduledoc """
  The bulk correction keeps the question navigation in a compact sticky header:
  one numbered box per question, prev/next chevrons and the URLs the ← / →
  shortcuts follow.
  """
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  defp question(n) do
    [
      %{
        "type" => "heading",
        "attrs" => %{"level" => 3, "partId" => "q-#{n}"},
        "content" => [%{"type" => "text", "text" => "Übersetzung #{n}"}]
      },
      %{
        "type" => "answerBlock",
        "attrs" => %{"answerId" => "a#{n}"},
        "content" => [%{"type" => "paragraph"}]
      }
    ]
  end

  setup do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    content = %{"type" => "doc", "content" => Enum.flat_map(1..3, &question/1)}
    exam = exam_fixture(scope: scope, status: "running", attrs: %{content: content})
    exam_submission_fixture(exam)

    %{teacher: teacher, exam: exam}
  end

  defp open(conn, teacher, exam, part_id) do
    conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/correction/bulk/#{part_id}")
  end

  defp attr(view, selector, name) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute(name)
    |> List.first()
  end

  test "one box per question, the current one marked", %{conn: conn} = ctx do
    {:ok, view, _html} = open(conn, ctx.teacher, ctx.exam, "q-2")

    for n <- 1..3, do: assert(has_element?(view, "#bulk-part-nav-q-#{n} a"))
    assert has_element?(view, ~s|#bulk-part-nav-q-2 a[aria-current="page"]|)
    refute has_element?(view, ~s|#bulk-part-nav-q-1 a[aria-current="page"]|)
  end

  test "the chevrons and the shortcut URLs point to the neighbours", %{conn: conn} = ctx do
    {:ok, view, _html} = open(conn, ctx.teacher, ctx.exam, "q-2")

    assert attr(view, "#bulk-prev-part", "href") == ~p"/exams/#{ctx.exam}/correction/bulk/q-1"
    assert attr(view, "#bulk-next-part", "href") == ~p"/exams/#{ctx.exam}/correction/bulk/q-3"

    assert attr(view, "#bulk-power-keys", "data-prev-url") ==
             ~p"/exams/#{ctx.exam}/correction/bulk/q-1"

    assert attr(view, "#bulk-power-keys", "data-next-url") ==
             ~p"/exams/#{ctx.exam}/correction/bulk/q-3"
  end

  test "the first question has no previous one", %{conn: conn} = ctx do
    {:ok, view, _html} = open(conn, ctx.teacher, ctx.exam, "q-1")

    assert has_element?(view, ~s|span#bulk-prev-part[aria-disabled="true"]|)
    assert attr(view, "#bulk-power-keys", "data-prev-url") == nil
  end

  test "marking the question done shows on its box", %{conn: conn} = ctx do
    {:ok, view, _html} = open(conn, ctx.teacher, ctx.exam, "q-2")

    assert has_element?(view, ~s|#bulk-part-nav-q-2 a[data-done="false"]|)

    view |> element("[data-bulk-power-toggle]") |> render_click()

    assert has_element?(view, ~s|#bulk-part-nav-q-2 a[data-done="true"]|)
  end

  test "the done badge in the header follows the toggle", %{conn: conn} = ctx do
    {:ok, view, _html} = open(conn, ctx.teacher, ctx.exam, "q-2")

    refute has_element?(view, "#bulk-corrected-badge")
    assert has_element?(view, ~s|#bulk-toggle-corrected[aria-pressed="false"]|)

    view |> element("#bulk-toggle-corrected") |> render_click()

    assert has_element?(view, "#bulk-corrected-badge")
    assert has_element?(view, ~s|#bulk-toggle-corrected[aria-pressed="true"]|)

    view |> element("#bulk-toggle-corrected") |> render_click()

    refute has_element?(view, "#bulk-corrected-badge")
  end

  test "the shortcuts are explained in a dialog", %{conn: conn} = ctx do
    {:ok, view, _html} = open(conn, ctx.teacher, ctx.exam, "q-2")

    refute has_element?(view, "#keys-modal")

    view |> element("#show-keys-modal") |> render_click()
    assert has_element?(view, "#keys-modal #keys-list")

    render_hook(view, "close_keys_modal", %{})
    refute has_element?(view, "#keys-modal")
  end
end
