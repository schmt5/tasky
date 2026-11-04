defmodule Tasky.Correction.ImagePinTest do
  use ExUnit.Case, async: true

  alias Tasky.Correction.AnswerKey
  alias Tasky.Correction.ImagePin

  defp circle(x, y, r),
    do: %{"pinId" => "p", "x" => x, "y" => y, "zone" => %{"shape" => "circle", "r" => r}}

  defp at(x, y), do: %{"pinId" => "p", "x" => x, "y" => y}

  describe "hit?/3" do
    test "a circle stays round on a wide image: the height counts in width units" do
      sample = circle(0.5, 0.5, 0.1)

      # 2:1 image — 0.1 of the width is 0.2 of the height.
      assert ImagePin.hit?(at(0.5, 0.69), sample, 2.0)
      refute ImagePin.hit?(at(0.5, 0.71), sample, 2.0)
      assert ImagePin.hit?(at(0.59, 0.5), sample, 2.0)
      refute ImagePin.hit?(at(0.61, 0.5), sample, 2.0)
    end

    test "on a tall image the circle is flatter in height units" do
      sample = circle(0.5, 0.5, 0.1)
      assert ImagePin.hit?(at(0.5, 0.54), sample, 0.5)
      refute ImagePin.hit?(at(0.5, 0.56), sample, 0.5)
    end

    test "a rectangle is centred on the pin, edges included" do
      sample = %{
        "pinId" => "p",
        "x" => 0.5,
        "y" => 0.5,
        "zone" => %{"shape" => "rect", "w" => 0.2, "h" => 0.1}
      }

      assert ImagePin.hit?(at(0.6, 0.55), sample, 1.0)
      refute ImagePin.hit?(at(0.61, 0.5), sample, 1.0)
      refute ImagePin.hit?(at(0.5, 0.56), sample, 1.0)
    end

    test "an unset pin, or a sample without a position, never hits" do
      refute ImagePin.hit?(%{"pinId" => "p", "x" => nil, "y" => nil}, circle(0.5, 0.5, 0.1), 1.0)

      refute ImagePin.hit?(
               at(0.5, 0.5),
               %{"pinId" => "p", "zone" => %{"shape" => "circle", "r" => 0.1}},
               1.0
             )
    end
  end

  describe "score/3 and verdict/2" do
    test "pairs pins by id and shares the points for a partial answer" do
      sample = [
        Map.put(circle(0.2, 0.2, 0.05), "pinId", "a"),
        Map.put(circle(0.8, 0.8, 0.05), "pinId", "b")
      ]

      both = [Map.put(at(0.8, 0.8), "pinId", "b"), Map.put(at(0.2, 0.2), "pinId", "a")]
      one = [Map.put(at(0.2, 0.2), "pinId", "a"), Map.put(at(0.2, 0.2), "pinId", "b")]

      assert ImagePin.score(both, sample, 1.0) == {2, 2}
      assert ImagePin.score(one, sample, 1.0) == {1, 2}
      assert ImagePin.score([], sample, 1.0) == {0, 2}

      assert ImagePin.verdict({2, 2}, 3) == "correct"
      assert ImagePin.verdict({0, 2}, 3) == "wrong"
      assert ImagePin.verdict({1, 2}, 3) == 1.5
      assert ImagePin.verdict({1, 3}, 1) == 0.25
      assert ImagePin.verdict({1, 2}, nil) == "wrong"
      assert ImagePin.verdict({0, 0}, 3) == nil
    end
  end

  describe "learner_pins/2" do
    test "keeps one entry per known pin, in the exam's order, clamped to the image" do
      value = [
        %{"pinId" => "b", "x" => 1.7, "y" => -1},
        %{"pinId" => "fremd", "x" => 0.1, "y" => 0.1},
        %{"pinId" => "b", "x" => 0.3, "y" => 0.3},
        "kaputt"
      ]

      assert ImagePin.learner_pins(["a", "b"], value) == [
               %{"pinId" => "a", "x" => nil, "y" => nil},
               %{"pinId" => "b", "x" => 1.0, "y" => 0.0}
             ]

      assert ImagePin.learner_pins(["a"], "nope") == :ignore
    end
  end

  describe "with AnswerKey" do
    test "split keeps only the pin ids in the content, merge puts the pins back" do
      pins = [
        circle(0.4, 0.5, 0.1),
        %{
          "pinId" => "q",
          "x" => 0.1,
          "y" => 0.1,
          "zone" => %{"shape" => "rect", "w" => 0.1, "h" => 0.1}
        }
      ]

      node = %{
        "type" => "imagePin",
        "attrs" => %{"answerId" => "img", "src" => "/a.png", "pins" => pins}
      }

      {content, answers} = AnswerKey.split(%{"type" => "doc", "content" => [node]})

      assert [%{"attrs" => %{"pins" => [%{"pinId" => "p"}, %{"pinId" => "q"}]}}] =
               content["content"]

      assert answers == %{"img" => pins}
      assert AnswerKey.merge(content, answers) == %{"type" => "doc", "content" => [node]}
    end

    test "sync_public_pins/2 takes the number of pins from the sample solution" do
      stale = %{
        "type" => "doc",
        "content" => [%{"type" => "imagePin", "attrs" => %{"answerId" => "img", "pins" => []}}]
      }

      synced = ImagePin.sync_public_pins(stale, %{"img" => [circle(0.4, 0.5, 0.1)]})
      assert [%{"attrs" => %{"pins" => [%{"pinId" => "p"}]}}] = synced["content"]

      assert [%{"attrs" => %{"pins" => []}}] = ImagePin.sync_public_pins(synced, %{})["content"]
    end
  end
end
