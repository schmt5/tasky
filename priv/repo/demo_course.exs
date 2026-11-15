# Demo course "Erdmännchen": a learning unit with information and a practice
# test that together use the editor's blocks (headings, callouts, lists,
# tables, quote, audio, single choice — also one radio group per table row —,
# multiple choice, gap, pin image, answer and essay field), each answer field
# with a sample solution. Meant for screenshots and for trying the app locally.
#
# Run with: mix run priv/repo/demo_course.exs
#
# Builds on priv/repo/dev_users.exs (run first, idempotent): the course
# belongs to the dev teacher and the dev student is enrolled. Skips if the
# teacher already has a course of this name — delete it in the app to rebuild.
#
# The documents are written the way the editor writes them: one
# answer-filled document per unit, split by `Tasky.Correction.AnswerKey` into
# the content learners get and the sample solution, both saved through the
# same `Tasky.Tasks` functions as the content and sample-solution tabs.

Code.eval_file(Path.join(__DIR__, "dev_users.exs"))

defmodule DemoCourse do
  @moduledoc false

  alias Tasky.{Accounts, Courses, ExamDoc, Repo, Tasks, Uploads}
  alias Tasky.Accounts.Scope
  alias Tasky.Correction.AnswerKey

  @course_name "Erdmännchen"

  def run(assets) do
    teacher = Accounts.get_user_by_email("lehrperson@tasky.test")
    student = Accounts.get_user_by_email("lernende@tasky.test")
    scope = Scope.for_user(teacher)

    if Repo.get_by(Courses.Course, name: @course_name, teacher_id: teacher.id) do
      IO.puts("Course \"#{@course_name}\" already exists for #{teacher.email} — skipped.")
    else
      {:ok, course} =
        Courses.create_course(scope, %{
          name: @course_name,
          description:
            "Wie leben Erdmännchen, und warum steht immer eines Wache? " <>
              "Eine Lerneinheit mit Infos und ein Übungstest."
        })

      facts(scope, course)
      practice_test(scope, course, assets)

      {:ok, _} = Courses.enroll_student(course.id, student.id)

      IO.puts("""
      Course "#{course.name}" created for #{teacher.email} with 2 learning units;
      #{student.email} is enrolled. Teacher view: /courses/#{course.id}
      """)
    end
  end

  # --- 1: Infos über Erdmännchen -------------------------------------------

  defp facts(scope, course) do
    unit = create_unit!(scope, course, 1, "Infos über Erdmännchen")

    save_unit!(
      scope,
      unit,
      doc([
        heading(1, "Das Erdmännchen"),
        %{
          "type" => "callout",
          "attrs" => %{"color" => "blue"},
          "content" => [
            p([bold("Lernziele")]),
            bullets([
              "Du weisst, wo Erdmännchen leben und wie ihr Körper gebaut ist.",
              "Du kannst erklären, wie Erdmännchen in der Gruppe zusammenleben."
            ])
          ]
        },
        p(
          "Erdmännchen sind kleine Raubtiere aus dem südlichen Afrika. Bekannt sind sie " <>
            "dafür, dass sie aufrecht auf den Hinterbeinen stehen und Ausschau halten."
        ),
        heading(2, "Steckbrief"),
        fact_table([
          {"Tierklasse", "Säugetier, Familie der Mangusten"},
          {"Lebensraum", "Trockene Savannen und Halbwüsten im südlichen Afrika (Kalahari)"},
          {"Grösse", "25–35 cm, dazu ein Schwanz von etwa 20 cm"},
          {"Gewicht", "600 g bis 1 kg"},
          {"Nahrung", "Vor allem Insekten und Larven, auch Skorpione, Spinnen und Eidechsen"},
          {"Gruppe", "10 bis 30 Tiere, manchmal mehr"}
        ]),
        heading(2, "Körper"),
        p(
          "Mit ihren langen Krallen graben Erdmännchen ihre Baue und suchen im Sand nach " <>
            "Futter. Beim Graben können sie die Ohren verschliessen, damit kein Sand " <>
            "hineinkommt. Die dunklen Ringe um die Augen wirken wie eine Sonnenbrille."
        ),
        heading(2, "Zusammenleben"),
        p(
          "Erdmännchen leben in Gruppen in unterirdischen Bauen mit vielen Eingängen. " <>
            "Während die anderen nach Futter graben, steht ein Tier als Wachposten auf den " <>
            "Hinterbeinen. Sieht es einen Feind, etwa einen Greifvogel oder einen Schakal, " <>
            "warnt es die Gruppe mit einem Ruf – und alle flüchten in den Bau. Helfer " <>
            "passen auf die Jungtiere auf, wie Babysitter."
        ),
        blockquote([
          text("Erdmännchen sind Säugetiere: Die Jungen trinken Milch von der Mutter.")
        ]),
        callout("yellow", [
          bold("Wusstest du? "),
          text(
            "Am Morgen stellen sich Erdmännchen in die Sonne und wärmen ihren Bauch. " <>
              "Dort ist das Fell dünn und die Haut dunkel."
          )
        ])
      ])
    )
  end

  # --- 2: Übungstest -------------------------------------------------------

  defp practice_test(scope, course, assets) do
    unit = create_unit!(scope, course, 2, "Übungstest: Erdmännchen")

    {:ok, map_src} =
      Uploads.save_task_image(unit.id, %Plug.Upload{
        path: Path.join(assets, "afrika.png"),
        filename: "afrika.png",
        content_type: "image/png"
      })

    # A is the sheep, B the meerkat. The titles must not give it away.
    {:ok, sound_a} = save_audio(unit, Path.join(assets, "schaf.mp3"))
    {:ok, sound_b} = save_audio(unit, Path.join(assets, "erdmaennchen.mp3"))

    save_unit!(
      scope,
      unit,
      doc(
        [
          heading(1, "Übungstest: Erdmännchen"),
          callout("yellow", [
            text("Beantworte alle Fragen. Nach der Abgabe siehst du die Musterlösung.")
          ]),
          question("Zu welcher Tierklasse gehören Erdmännchen?")
        ] ++
          single_choice("g_klasse", [
            {"Säugetiere", true},
            {"Reptilien", false},
            {"Vögel", false}
          ]) ++
          [
            question("Richtig oder falsch?"),
            p("Kreuze in jeder Zeile an."),
            choice_table("Aussage", ["richtig", "falsch"], [
              {"Erdmännchen leben allein.", "falsch"},
              {"Ein Wachposten warnt die Gruppe vor Feinden.", "richtig"},
              {"Erdmännchen fressen vor allem Gras.", "falsch"}
            ]),
            empty(),
            question("Was fressen Erdmännchen?"),
            p("Kreuze alle richtigen an."),
            checklist([
              {"Insekten", true},
              {"Skorpione", true},
              {"Gras", false},
              {"Spinnen", true}
            ]),
            question("Ergänze den Satz."),
            p([text("Erdmännchen leben im südlichen "), gap("Afrika"), text(".")]),
            question("Wo leben Erdmännchen?"),
            p("Setze den Pin in das Gebiet, in dem Erdmännchen leben."),
            # 495 × 490 px; the Kalahari, centred on Botswana.
            image_pin(map_src, "Karte von Afrika mit Ländern", 495 / 490, [
              {0.556, 0.751, 0.11}
            ]),
            empty(),
            question("Welches Geräusch macht ein Erdmännchen?"),
            p("Hör dir beide Geräusche an."),
            audio(sound_a, "Geräusch A", 2),
            audio(sound_b, "Geräusch B", 2)
          ] ++
          single_choice("g_geraeusch", [{"Geräusch A", false}, {"Geräusch B", true}]) ++
          [
            question("Nenne einen Feind des Erdmännchens."),
            answer("Adler;Greifvogel;Habicht;Falke;Schakal;Schlange"),
            question("Warum steht bei Erdmännchen immer ein Tier Wache?"),
            p("Erkläre in zwei bis drei Sätzen."),
            essay(
              "Während die Gruppe nach Futter gräbt, achtet der Wachposten auf Feinde wie " <>
                "Greifvögel oder Schakale. Sieht er einen, warnt er die anderen mit einem Ruf, " <>
                "und alle können sich rechtzeitig im Bau in Sicherheit bringen."
            ),
            empty()
          ]
      )
    )
  end

  defp save_audio(unit, path) do
    Uploads.save_task_audio(unit.id, %Plug.Upload{
      path: path,
      filename: Path.basename(path),
      content_type: "audio/mpeg"
    })
  end

  # --- Saving --------------------------------------------------------------

  defp create_unit!(scope, course, position, name) do
    {:ok, task} =
      Tasks.create_task(scope, %{
        course_id: course.id,
        name: name,
        position: position,
        status: "open",
        solution_release_mode: "on_complete"
      })

    task
  end

  # Saves an answer-filled document as content + sample solution.
  defp save_unit!(scope, task, filled) do
    # Ids first: the sample solution is keyed by them, so content and solution
    # must be split from the same stamped document.
    filled = filled |> AnswerKey.ensure_ids() |> ExamDoc.ensure_part_ids()
    {content, _answers} = AnswerKey.split(filled)
    {:ok, task} = Tasks.save_task_content(scope, task, content)

    filled
    |> ExamDoc.split_content_into_parts("answer_fields")
    |> Enum.reduce(task, fn part, task ->
      {:ok, task} = Tasks.save_sample_solution_part(scope, task, part.id, part.nodes)
      task
    end)
  end

  # --- Document building ---------------------------------------------------

  defp doc(nodes), do: %{"type" => "doc", "content" => nodes}

  defp text(text, marks \\ []), do: %{"type" => "text", "text" => text, "marks" => marks}
  defp bold(text), do: text(text, [%{"type" => "bold"}])

  defp p(inlines) when is_list(inlines), do: %{"type" => "paragraph", "content" => inlines}
  defp p(text) when is_binary(text), do: p([text(text)])
  defp empty, do: %{"type" => "paragraph"}

  defp heading(level, title),
    do: %{"type" => "heading", "attrs" => %{"level" => level}, "content" => [text(title)]}

  # A question: an h3 starts a part (see Tasky.ExamDoc).
  defp question(title), do: heading(3, title)

  defp callout(color, inlines),
    do: %{"type" => "callout", "attrs" => %{"color" => color}, "content" => [p(inlines)]}

  defp blockquote(inlines), do: %{"type" => "blockquote", "content" => [p(inlines)]}

  defp bullets(items) do
    %{
      "type" => "bulletList",
      "content" => for(item <- items, do: %{"type" => "listItem", "content" => [p(item)]})
    }
  end

  # Alternatives in a sample solution are separated by `;`
  # (see Tasky.Correction.AnswerVariants).
  defp gap(solution), do: %{"type" => "lueckentext", "content" => [text(solution)]}

  defp answer(solution), do: %{"type" => "answerBlock", "content" => [p(solution)]}

  defp essay(solution),
    do: %{"type" => "answerBlock", "attrs" => %{"rich" => true}, "content" => [p(solution)]}

  # Multiple choice: `{label, correct?}`.
  defp checklist(items) do
    %{
      "type" => "taskList",
      "content" =>
        for {label, correct?} <- items do
          %{"type" => "taskItem", "attrs" => %{"checked" => correct?}, "content" => [p(label)]}
        end
    }
  end

  # Single choice: one radio group, `{label, correct?}` per option.
  defp single_choice(group_id, options) do
    options
    |> Enum.with_index()
    |> Enum.map(fn {{label, correct?}, i} ->
      p([radio(group_id, "o_#{group_id}_#{i}", correct?), text(" " <> label)])
    end)
  end

  defp radio(group_id, option_id, checked?) do
    %{
      "type" => "choice",
      "attrs" => %{"groupId" => group_id, "optionId" => option_id, "checked" => checked?}
    }
  end

  # A read-only two-column table: label, value.
  defp fact_table(rows) do
    %{
      "type" => "table",
      "content" =>
        for {label, value} <- rows do
          row([cell("tableHeader", [p([bold(label)])]), cell("tableCell", [p(value)])])
        end
    }
  end

  # A table whose every row is one single-choice question: the row label,
  # then one radio per column.
  defp choice_table(first_header, columns, rows) do
    header =
      row(for label <- [first_header | columns], do: cell("tableHeader", [p([bold(label)])]))

    body =
      for {{label, correct_column}, r} <- Enum.with_index(rows) do
        group = "g_row_#{r}"

        radios =
          for {column, c} <- Enum.with_index(columns) do
            cell("tableCell", [p([radio(group, "o_#{r}_#{c}", column == correct_column)])])
          end

        row([cell("tableCell", [p(label)]) | radios])
      end

    %{"type" => "table", "content" => [header | body]}
  end

  defp row(cells), do: %{"type" => "tableRow", "content" => cells}

  defp cell(type, content),
    do: %{
      "type" => type,
      "attrs" => %{"colspan" => 1, "rowspan" => 1, "colwidth" => nil},
      "content" => content
    }

  # `pins` in the sample solution: where each pin belongs (relative to the
  # image, 0..1 from the top left) and how far off still counts.
  defp image_pin(src, alt, aspect, pins) do
    %{
      "type" => "imagePin",
      "attrs" => %{
        "src" => src,
        "alt" => alt,
        "aspect" => aspect,
        "pins" =>
          for {{x, y, r}, i} <- Enum.with_index(pins, 1) do
            %{
              "pinId" => "pin-#{i}",
              "x" => x,
              "y" => y,
              "zone" => %{"shape" => "circle", "r" => r}
            }
          end
      }
    }
  end

  defp audio(src, title, max_plays) do
    %{
      "type" => "audio",
      "attrs" => %{
        "audioId" => Ecto.UUID.generate(),
        "src" => src,
        "title" => title,
        "maxPlays" => max_plays
      }
    }
  end
end

DemoCourse.run(Path.join(__DIR__, "demo_assets"))
