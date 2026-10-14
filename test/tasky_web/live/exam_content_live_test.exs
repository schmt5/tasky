defmodule TaskyWeb.ExamContentLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures

  alias Tasky.Exams

  defp two_part_content do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3},
          "content" => [%{"type" => "text", "text" => "Frage Eins"}]
        },
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "Inhalt eins"}]
        },
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3},
          "content" => [%{"type" => "text", "text" => "Frage Zwei"}]
        },
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "Inhalt zwei"}]
        }
      ]
    }
  end

  defp heading(text) do
    %{
      "type" => "heading",
      "attrs" => %{"level" => 3},
      "content" => [%{"type" => "text", "text" => text}]
    }
  end

  defp answer_block(id) do
    %{
      "type" => "answerBlock",
      "attrs" => %{"answerId" => id},
      "content" => [%{"type" => "paragraph"}]
    }
  end

  defp task_list(ids) do
    %{
      "type" => "taskList",
      "content" =>
        Enum.map(ids, fn id ->
          %{
            "type" => "taskItem",
            "attrs" => %{"checked" => false, "answerId" => id},
            "content" => [
              %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => id}]}
            ]
          }
        end)
    }
  end

  # q-1: text only, q-2: checkboxes only, q-3: both.
  defp mixed_answer_content do
    %{
      "type" => "doc",
      "content" => [
        heading("Text"),
        answer_block("t1"),
        heading("Ankreuzen"),
        task_list(["c1", "c2"]),
        heading("Gemischt"),
        answer_block("t2"),
        task_list(["c3"])
      ]
    }
  end

  defp create_exam(content) do
    teacher = user_fixture(%{role: "teacher"})
    scope = user_scope_fixture(teacher)
    {:ok, exam} = Exams.create_exam(scope, %{name: "Test Prüfung", content: content})
    %{teacher: teacher, scope: scope, exam: exam}
  end

  defp open_musterloesung(conn, teacher, exam) do
    conn = log_in_user(conn, teacher)
    live(conn, ~p"/exams/#{exam}/content?tab=musterloesung")
  end

  describe "Musterlösung tab" do
    test "renders all parts stacked with one shared toolbar slot", %{conn: conn} do
      %{teacher: teacher, exam: exam} = create_exam(two_part_content())
      {:ok, _view, html} = open_musterloesung(conn, teacher, exam)

      # both part editors are present at once
      assert html =~ ~s(id="sample-solution-part-editor-#{exam.id}-q-1")
      assert html =~ ~s(id="sample-solution-part-editor-#{exam.id}-q-2")

      # both points cards are present
      assert html =~ "Frage Eins"
      assert html =~ "Frage Zwei"

      # exactly one shared toolbar slot
      assert html =~ ~s(id="solution-toolbar-#{exam.id}")

      # the TEIL navigator is gone
      refute html =~ "Vorheriger Teil"
      refute html =~ "Nächster Teil"
    end

    test "shows the empty state when the exam has no questions", %{conn: conn} do
      %{teacher: teacher, exam: exam} = create_exam(%{"type" => "doc", "content" => []})
      {:ok, _view, html} = open_musterloesung(conn, teacher, exam)

      assert html =~ "Noch keine Frage vorhanden"
      refute html =~ ~s(id="solution-toolbar-#{exam.id}")
    end

    test "adjust_max_points targets only the given part", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = create_exam(two_part_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      render_click(view, "adjust_max_points", %{"direction" => "up", "part-id" => "q-2"})

      exam = Exams.get_exam!(scope, exam.id)
      assert exam.sample_solution_points == %{"q-2" => 0.25}
    end

    test "set_max_points uses the part_id from the form", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = create_exam(two_part_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      render_change(view, "set_max_points", %{"points" => "6", "part_id" => "q-1"})

      exam = Exams.get_exam!(scope, exam.id)
      assert exam.sample_solution_points == %{"q-1" => 6}
    end

    test "auto-correct toggles are scoped per part", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = create_exam(two_part_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      render_click(view, "toggle_auto_correct", %{"part-id" => "q-1"})
      render_click(view, "toggle_text_option", %{"part-id" => "q-1", "option" => "ignore_case"})
      # q-2 has auto_correct off, so its sub-flag toggle must be a no-op
      render_click(view, "toggle_text_option", %{"part-id" => "q-2", "option" => "ignore_case"})

      exam = Exams.get_exam!(scope, exam.id)
      assert get_in(exam.ai_correction_config, ["q-1", "auto_correct"]) == true
      assert get_in(exam.ai_correction_config, ["q-1", "ignore_case"]) == true
      refute get_in(exam.ai_correction_config, ["q-2", "ignore_case"])
    end

    test "disabling auto-correct resets the sub-flags of that part", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = create_exam(two_part_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      render_click(view, "toggle_auto_correct", %{"part-id" => "q-1"})
      render_click(view, "toggle_text_option", %{"part-id" => "q-1", "option" => "ignore_case"})
      render_click(view, "toggle_auto_correct", %{"part-id" => "q-1"})

      exam = Exams.get_exam!(scope, exam.id)
      assert get_in(exam.ai_correction_config, ["q-1", "auto_correct"]) == false
      assert get_in(exam.ai_correction_config, ["q-1", "ignore_case"]) == false
    end
  end

  describe "correction options per answer type" do
    test "text options appear only where text answers are compared", %{conn: conn} do
      %{teacher: teacher, exam: exam} = create_exam(mixed_answer_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      for key <- ~w(ignore_case ignore_spelling ignore_punctuation) do
        assert has_element?(view, "##{key}-q-1")
        refute has_element?(view, "##{key}-q-2")
        assert has_element?(view, "##{key}-q-3")
      end

      # Checkbox-only: an explanation instead of options that would do nothing.
      assert has_element?(view, "#checkbox-only-note-q-2")
      # Mixed: the options say they skip the checkboxes.
      assert has_element?(view, "#text-options-note-q-3")
      refute has_element?(view, "#text-options-note-q-1")
    end

    test "\"Satzzeichen ignorieren\" is stored per part", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = create_exam(mixed_answer_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      render_click(view, "toggle_auto_correct", %{"part-id" => "q-1"})
      view |> element("#ignore_punctuation-q-1") |> render_click()

      exam = Exams.get_exam!(scope, exam.id)
      assert get_in(exam.ai_correction_config, ["q-1", "ignore_punctuation"]) == true

      # Switching auto-correction off clears it with the other text options.
      render_click(view, "toggle_auto_correct", %{"part-id" => "q-1"})
      exam = Exams.get_exam!(scope, exam.id)
      assert get_in(exam.ai_correction_config, ["q-1", "ignore_punctuation"]) == false
    end

    test "an unknown option is ignored", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = create_exam(mixed_answer_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      render_click(view, "toggle_auto_correct", %{"part-id" => "q-1"})
      render_click(view, "toggle_text_option", %{"part-id" => "q-1", "option" => "bogus"})

      exam = Exams.get_exam!(scope, exam.id)
      refute Map.has_key?(exam.ai_correction_config["q-1"], "bogus")
    end
  end

  describe "\"Mehrere Musterlösungen\" help dialog" do
    test "opens and closes, and never duplicates its DOM id across parts", %{conn: conn} do
      %{teacher: teacher, exam: exam} = create_exam(two_part_content())
      {:ok, view, html} = open_musterloesung(conn, teacher, exam)

      # One trigger per question card, but the dialog itself is closed.
      assert count(html, "Mehrere Musterlösungen pro Antwortfeld") == 2
      refute html =~ ~s(id="alternatives-help-modal")

      html = render_click(view, "open_alternatives_help")

      # The dialog lives outside the part loop: two question cards must still
      # yield exactly one <dialog>, otherwise the DOM id is duplicated.
      assert count(html, ~s(id="alternatives-help-modal")) == 1
      assert html =~ "rasch; flink; zügig; geschwind"

      html = render_click(view, "close_alternatives_help")
      refute html =~ ~s(id="alternatives-help-modal")
    end
  end

  defp count(haystack, needle), do: length(String.split(haystack, needle)) - 1

  describe "save_sample_solution_part/3 with stale structs" do
    # The stacked Musterlösung view autosaves every part independently, so a
    # request can arrive carrying state read before another part's save
    # committed. The row lock inside save_sample_solution_part must splice
    # against the fresh DB state, never the stale struct.
    test "two saves based on the same stale exam struct do not clobber each other" do
      %{scope: scope, exam: exam} = create_exam(two_part_content())
      stale = Exams.get_exam!(scope, exam.id)

      part_one_nodes = [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3},
          "content" => [%{"type" => "text", "text" => "Frage Eins"}]
        },
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "Antwort eins NEU"}]
        }
      ]

      part_two_nodes = [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3},
          "content" => [%{"type" => "text", "text" => "Frage Zwei"}]
        },
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "Antwort zwei NEU"}]
        }
      ]

      {:ok, _} = Exams.save_sample_solution_part(scope, stale, "q-1", part_one_nodes)
      # second save still uses the stale struct (its content predates save #1)
      {:ok, _} = Exams.save_sample_solution_part(scope, stale, "q-2", part_two_nodes)

      reloaded = Exams.get_exam!(scope, exam.id)
      json = Jason.encode!(reloaded.content)

      assert json =~ "Antwort eins NEU"
      assert json =~ "Antwort zwei NEU"
    end
  end
end
