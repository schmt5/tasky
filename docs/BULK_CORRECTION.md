# Bulk Correction

A faster way to correct an exam: instead of opening each student's submission
one by one, the teacher corrects **one question at a time across the whole
class** — and identical answers are graded together.

## The idea

In a class of 25, a single question often only produces a handful of *distinct*
answers. Twelve students write "fliegen", six write "Fliegen", four leave it
blank, three misspell it. That's really only four things to judge — not 25.

Bulk correction is built around that observation:

> **Group identical answers, judge each group once, apply the verdict to every
> student in the group.**

So the teacher makes 4 decisions instead of 25. The bigger the class, the more
this pays off.

## The flow

**1. Pick a question.**
The teacher starts from the correction overview and jumps into one question
(one "part") for the entire class.

**2. See the answers, grouped.**
All students' answers to that question are collected and bucketed by what they
actually wrote. Each bucket shows the answer, how many students gave it, and who
they are. The most common answers come first. Blank answers form their own
"no answer" group.

**3. Judge each group.**
For every group the teacher picks: **correct**, **partly correct**, or
**wrong**. One click (or one keystroke — J / K / L) settles that answer for
*everyone* who wrote it. Tab moves to the next group, so a whole question can be
graded in seconds without leaving the keyboard.

**4. Move on.**
"Mark as done" finalises the question for the whole class, and the teacher moves
to the next one. When every question is done, the exam is ready for grading.

## A helpful head start

To save even more clicks, the system **pre-judges** answers in the background by
comparing them to the sample solution. When a student submits — or when the
teacher edits the sample solution — each answer is automatically marked correct
or wrong based on whether it matches.

The teacher can fine-tune how strict that matching is, per question:

- **ignore upper/lowercase** — "fliegen" and "Fliegen" count the same;
- **fuzzy spelling** — small typos still count as correct;
- a sample answer can list several accepted alternatives, separated by `;`
  (e.g. `rasch; flink; zügig`).

This is just a suggestion, not a final verdict. The bulk view shows each group
already coloured with the system's guess, so the teacher mostly just confirms —
and only clicks when they disagree. When they mark a question done, any group
they didn't touch keeps the system's suggestion.

## Why it's nice

- **Fewer decisions** — one judgement per *distinct answer*, not per student.
- **Consistency** — everyone who wrote the same thing automatically gets the
  same mark.
- **A running start** — the auto-suggestions mean many questions just need a
  quick glance and a confirmation.
- **Keyboard-fast** — J / K / L to judge, Tab to advance, Enter to finish.

## In short

Correct by *question*, not by *student*. Answers that are the same get bundled
and judged together. The system pre-fills its best guess so the teacher mostly
confirms — turning what used to be hundreds of individual judgements into a
handful per question.
