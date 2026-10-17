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

    test "the sidebar lists the active options without descriptions", %{conn: conn} do
      %{teacher: teacher, exam: exam} = create_exam(mixed_answer_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      assert view |> element("#correction-options-summary-q-1") |> render() =~
               "Keine Korrekturoptionen aktiv"

      assert view |> element("#correction-options-summary-q-2") |> render() =~
               "Multiple-Choice: pro Checkbox"

      refute has_element?(view, "#correction-options-modal")
    end
  end

  describe "Korrekturoptionen dialog" do
    defp open_options(view, part_id) do
      view |> element("#correction-options-btn-#{part_id}") |> render_click()
      assert has_element?(view, "#correction-options-modal")
    end

    # Text options are disabled until auto-correction is on, as in the browser.
    defp enable_auto_correct(view, part_id) do
      view
      |> form("#correction-options-form-#{part_id}", %{"options" => %{"auto_correct" => "true"}})
      |> render_change()
    end

    defp submit_options(view, part_id, params) do
      view
      |> form("#correction-options-form-#{part_id}", %{"options" => params})
      |> render_submit()
    end

    test "nothing is saved before \"Übernehmen\"", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = create_exam(mixed_answer_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      open_options(view, "q-1")

      view
      |> form("#correction-options-form-q-1", %{"options" => %{"auto_correct" => "true"}})
      |> render_change()

      view |> element("#correction-options-modal .modal-backdrop") |> render_click()

      refute has_element?(view, "#correction-options-modal")
      assert Exams.get_exam!(scope, exam.id).ai_correction_config == %{}
    end

    test "the ± buttons step the points in the dialog, plus left", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = create_exam(mixed_answer_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      open_options(view, "q-1")
      view |> element("#options_max_points-up") |> render_click()
      view |> element("#options_max_points-up") |> render_click()
      view |> element("#options_max_points-down") |> render_click()

      assert has_element?(view, ~s(#options_max_points[value="0.25"]))

      submit_options(view, "q-1", %{})
      assert Exams.get_exam!(scope, exam.id).sample_solution_points == %{"q-1" => 0.25}
    end

    test "applies points and options of one part and summarizes them", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = create_exam(mixed_answer_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      open_options(view, "q-1")
      enable_auto_correct(view, "q-1")

      submit_options(view, "q-1", %{
        "max_points" => "3",
        "auto_correct" => "true",
        "ignore_case" => "true",
        "ignore_punctuation" => "true"
      })

      refute has_element?(view, "#correction-options-modal")

      exam = Exams.get_exam!(scope, exam.id)
      assert exam.sample_solution_points == %{"q-1" => 3}
      assert get_in(exam.ai_correction_config, ["q-1", "auto_correct"]) == true
      assert get_in(exam.ai_correction_config, ["q-1", "ignore_case"]) == true
      assert get_in(exam.ai_correction_config, ["q-1", "ignore_spelling"]) == false
      refute Map.has_key?(exam.ai_correction_config, "q-2")

      summary = view |> element("#correction-options-summary-q-1") |> render()
      assert summary =~ "Auto-Korrektur"
      assert summary =~ "Gross-/Kleinschreibung ignorieren"
      assert summary =~ "Satzzeichen ignorieren"
      refute summary =~ "Rechtschreibung ignorieren"
      refute summary =~ "nicht bewertet"
    end

    test "text options go off together with auto-correction", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = create_exam(mixed_answer_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      open_options(view, "q-1")
      enable_auto_correct(view, "q-1")
      submit_options(view, "q-1", %{"auto_correct" => "true", "ignore_punctuation" => "true"})

      open_options(view, "q-1")
      submit_options(view, "q-1", %{"auto_correct" => "false"})

      exam = Exams.get_exam!(scope, exam.id)
      assert get_in(exam.ai_correction_config, ["q-1", "auto_correct"]) == false
      assert get_in(exam.ai_correction_config, ["q-1", "ignore_punctuation"]) == false
    end

    test "text options appear only where text answers are compared", %{conn: conn} do
      %{teacher: teacher, exam: exam} = create_exam(mixed_answer_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      open_options(view, "q-1")
      assert has_element?(view, "#options_ignore_case")
      refute has_element?(view, "#checkbox-scoring")
      refute has_element?(view, "#text-options-note")

      open_options(view, "q-2")
      refute has_element?(view, "#options_ignore_case")
      assert has_element?(view, "#checkbox-scoring")

      # Mixed: the text options say they skip the checkboxes.
      open_options(view, "q-3")
      assert has_element?(view, "#options_ignore_case")
      assert has_element?(view, "#text-options-note")
    end

    test "a part of only checkboxes has no auto-correction switch", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = create_exam(mixed_answer_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      open_options(view, "q-2")
      assert has_element?(view, "#auto-correct-always-note")
      refute has_element?(view, "#options_auto_correct")

      submit_options(view, "q-2", %{"max_points" => "2"})

      exam = Exams.get_exam!(scope, exam.id)
      assert Exams.auto_correct_part?(exam, "q-2")

      assert view |> element("#correction-options-summary-q-2") |> render() =~
               "Auto-Korrektur"

      # Mixed: the switch stays, and it is off by default.
      open_options(view, "q-3")
      refute has_element?(view, "#auto-correct-always-note")
      assert has_element?(view, "#options_auto_correct")
      refute Exams.auto_correct_part?(exam, "q-3")
    end

    test "the checkbox scoring rule is stored per part", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = create_exam(mixed_answer_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      open_options(view, "q-2")
      assert has_element?(view, ~s(#checkbox-scoring-per_checkbox[aria-checked="true"]))

      refute has_element?(view, "#checkbox-scoring-deduction")
      view |> element("#checkbox-scoring-all_or_nothing") |> render_click()

      submit_options(view, "q-2", %{"checkbox_rule" => "all_or_nothing"})

      exam = Exams.get_exam!(scope, exam.id)
      assert Exams.checkbox_scoring(exam, "q-2") == %{rule: "all_or_nothing"}
      assert Exams.checkbox_scoring(exam, "q-3").rule == "per_checkbox"

      assert view |> element("#correction-options-summary-q-2") |> render() =~
               "Multiple-Choice: alles oder nichts"
    end

    test "points per answer field are offered only with several fields", %{conn: conn} do
      %{teacher: teacher, exam: exam} = create_exam(mixed_answer_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      open_options(view, "q-1")
      refute has_element?(view, "#options_custom_points")

      open_options(view, "q-2")
      assert has_element?(view, "#options_custom_points")
    end

    test "a custom distribution starts from the equal split and sets the total", %{conn: conn} do
      %{teacher: teacher, scope: scope, exam: exam} = create_exam(mixed_answer_content())
      {:ok, view, _html} = open_musterloesung(conn, teacher, exam)

      open_options(view, "q-3")

      view
      |> form("#correction-options-form-q-3", %{
        "options" => %{"max_points" => "2", "custom_points" => "true"}
      })
      |> render_change()

      # 2 points over the text field and the checkbox: 1 each.
      assert has_element?(view, ~s(#options-block-points-t2[value="1"]))

      submit_options(view, "q-3", %{
        "custom_points" => "true",
        "block_points" => %{"t2" => "1.5", "c3" => "0.5"}
      })

      exam = Exams.get_exam!(scope, exam.id)
      assert exam.sample_solution_block_points == %{"q-3" => %{"t2" => 1.5, "c3" => 0.5}}
      assert exam.sample_solution_points == %{"q-3" => 2}

      assert view |> element("#correction-options-summary-q-3") |> render() =~
               "Punkte pro Antwortfeld"
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
