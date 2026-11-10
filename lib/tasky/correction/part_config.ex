defmodule Tasky.Correction.PartConfig do
  @moduledoc """
  The correction options of one question (part), as the sample solution's
  "Korrekturoptionen" dialog sets them. Shared by exams
  (`exam.ai_correction_config[part_id]`) and learning units
  (`task.correction_config[part_id]`), so both read and write the same keys
  under the same rules:

    * `"auto_correct"` — compare the part's text answers with the sample
      solution. A part of only checkboxes, radios and pin images is always
      compared, whatever the flag says (`choice_only_blocks?/1`).
    * `"ignore_case"`, `"ignore_spelling"`, `"ignore_punctuation"` — the text
      options, read by `Tasky.Correction.StringComparator.match_opts/1`. They
      only hold while `"auto_correct"` is on.
    * `"checkbox_scoring"` — `"per_checkbox"` or `"all_or_nothing"`, see
      `Tasky.Grading.checkbox_rules/0`.

  Only the defaults differ: an exam question starts with everything off, a
  learning-unit question with auto-correction and `"ignore_case"` on, so a new
  unit checks itself as before.
  """

  alias Tasky.Grading

  @flags ~w(auto_correct ignore_case ignore_spelling ignore_punctuation)

  @doc "The boolean keys of a part config."
  def flags, do: @flags

  @doc """
  The config of a question nobody set options for yet: all off for an exam,
  auto-correction ignoring case for a learning unit.
  """
  def defaults(:exam), do: %{}
  def defaults(:task), do: %{"auto_correct" => true, "ignore_case" => true}

  @doc """
  The stored config of `part_id` in `configs` (a map `part_id => config`),
  over `defaults`.
  """
  def get(configs, part_id, defaults \\ %{}) when is_binary(part_id) do
    case Map.get(configs || %{}, part_id) do
      config when is_map(config) -> Map.merge(defaults, config)
      _ -> defaults
    end
  end

  @doc "Whether `key` is set in the part config."
  def flag?(config, key) when key in @flags, do: Map.get(config || %{}, key) == true

  @doc """
  A part's checkbox scoring rule, `"per_checkbox"` unless set. A rule that no
  longer exists reads as `"per_checkbox"`.
  """
  def checkbox_rule(config) do
    case Map.get(config || %{}, "checkbox_scoring") do
      rule when is_binary(rule) ->
        if rule in Grading.checkbox_rules(), do: rule, else: "per_checkbox"

      _ ->
        "per_checkbox"
    end
  end

  @doc """
  `configs` with `given` (string keys, as the dialog submits them) applied to
  `part_id`. A key left out of `given` keeps the stored value; the text
  options are switched off together with auto-correction.
  """
  def put(configs, part_id, given, defaults \\ %{}) when is_binary(part_id) and is_map(given) do
    current = get(configs, part_id, defaults)
    auto? = Map.get(given, "auto_correct", current["auto_correct"]) == true

    flags =
      Map.new(@flags, fn key ->
        value = Map.get(given, key, current[key]) == true
        {key, if(key == "auto_correct", do: auto?, else: auto? and value)}
      end)

    rule =
      checkbox_rule(%{
        "checkbox_scoring" => Map.get(given, "checkbox_scoring", current["checkbox_scoring"])
      })

    part_config =
      current
      |> Map.merge(flags)
      |> Map.put("checkbox_scoring", rule)

    Map.put(configs || %{}, part_id, part_config)
  end

  @doc """
  Whether `blocks` (from `Tasky.AI.NodePatcher.list_answer_blocks/1`) are all
  checkboxes, radios or pin images, and there is at least one. A tick or a pin
  compares exactly against the sample solution, so such a part is always
  auto-corrected.
  """
  def choice_only_blocks?([_ | _] = blocks),
    do: Enum.all?(blocks, &(&1.type in ["taskItem", "choice", "imagePin"]))

  def choice_only_blocks?(_blocks), do: false
end
