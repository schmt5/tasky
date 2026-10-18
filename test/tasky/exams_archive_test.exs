defmodule Tasky.ExamsArchiveTest do
  use Tasky.DataCase, async: true

  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  setup do
    scope = user_scope_fixture(user_fixture(%{role: "teacher"}))
    %{scope: scope}
  end

  test "archived exams leave the list and show up in the archive", %{scope: scope} do
    active = exam_fixture(scope: scope, status: "finished")
    archived = exam_fixture(scope: scope, status: "finished", archived: true)

    assert Enum.map(Exams.list_exams(scope), & &1.id) == [active.id]
    assert Enum.map(Exams.list_exams(scope, archived: true), & &1.id) == [archived.id]
    assert Exams.count_archived_exams(scope) == 1
  end

  test "any status can be archived, and restoring keeps it", %{scope: scope} do
    exam = exam_fixture(scope: scope, status: "running")

    assert {:ok, archived} = Exams.archive_exam(scope, exam)
    assert Exams.archived?(archived)
    assert archived.status == "running"

    assert {:ok, restored} = Exams.unarchive_exam(scope, archived)
    refute Exams.archived?(restored)
    assert restored.status == "running"
  end

  test "another teacher can neither archive nor restore", %{scope: scope} do
    other = user_scope_fixture(user_fixture(%{role: "teacher"}))
    exam = exam_fixture(scope: scope)

    assert {:error, :unauthorized} = Exams.archive_exam(other, exam)

    {:ok, archived} = Exams.archive_exam(scope, exam)
    assert {:error, :unauthorized} = Exams.unarchive_exam(other, archived)
  end

  test "archived is no longer a status", %{scope: scope} do
    exam = exam_fixture(scope: scope, status: "finished")

    assert {:error, :invalid_transition} = Exams.update_exam_status(scope, exam, "archived")
  end
end
