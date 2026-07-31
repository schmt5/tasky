// The editor toolbar: formatting, lists, question/answer inserts, tables,
// image upload and the save-status pill. Rendered inline by the editor or
// standalone by SharedSolutionToolbar (bound to the focused part editor).

import { Children, useRef, useState, type ReactNode } from "react";
import { useEditorState } from "@tiptap/react";
import type { Editor } from "@tiptap/core";
// Imported for their command typings (module augmentation) — the packages
// are part of the editor bundle anyway.
import "@tiptap/starter-kit";
import "@tiptap/extension-highlight";
import "@tiptap/extension-text-style";
import "@tiptap/extension-table";
import "@tiptap/extension-image";
import "@tiptap/extension-list/task-list";
import {
  BoldIcon,
  ItalicIcon,
  UnderlineIcon,
  H1Icon,
  H2Icon,
  ListBulletIcon,
  QuestionMarkCircleIcon,
  NumberedListIcon,
  ChatBubbleLeftEllipsisIcon,
  InformationCircleIcon,
  PhotoIcon,
  TableCellsIcon,
  PaintBrushIcon,
  ArrowUturnLeftIcon,
  ArrowUturnRightIcon,
} from "@heroicons/react/24/outline";
import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import * as Tabs from "@radix-ui/react-tabs";
import * as Tooltip from "@radix-ui/react-tooltip";

import {
  CALLOUT_COLORS,
  DEFAULT_CALLOUT_COLOR,
  HIGHLIGHT_COLORS,
  TEXT_COLORS,
  type CalloutColor,
} from "./constants";
import {
  TextColorIcon,
  FreitextIcon,
  FreitextAbcIcon,
  LueckentextIcon,
  MultipleChoiceIcon,
  AddRowAboveIcon,
  AddRowBelowIcon,
  RemoveRowIcon,
  AddColumnLeftIcon,
  AddColumnRightIcon,
  RemoveColumnIcon,
  HeaderRowIcon,
  RemoveTableIcon,
} from "./icons";

export interface ToolbarProps {
  editor: Editor;
  status: string;
  errorMsg?: string | null;
  hideAnswers?: boolean;
  correctionMode?: boolean;
  hideQuestion?: boolean;
  uploadImage?: ((file: File) => Promise<{ url: string }>) | null;
  lockHintVisible?: boolean;
  lockHintEnabled?: boolean;
  lockHintText?: string;
}

export function Toolbar({
  editor,
  status,
  errorMsg,
  hideAnswers = false,
  correctionMode = false,
  hideQuestion = false,
  uploadImage = null,
  lockHintVisible = false,
  lockHintEnabled = false,
  lockHintText = "Der Aufgabentext kann nicht bearbeitet werden – schreibe deine Antwort in ein Antwortfeld.",
}: ToolbarProps) {
  // Subscribe directly to editor transactions so the active-state reflects
  // selection/format changes instantly, independent of the autosave cadence.
  const active = useEditorState({
    editor,
    selector: ({ editor }) => ({
      bold: editor.isActive("bold"),
      underline: editor.isActive("underline"),
      italic: editor.isActive("italic"),
      h1: editor.isActive("heading", { level: 1 }),
      h2: editor.isActive("heading", { level: 2 }),
      h3: editor.isActive("heading", { level: 3 }),
      bulletList: editor.isActive("bulletList"),
      orderedList: editor.isActive("orderedList"),
      taskList: editor.isActive("taskList"),
      lueckentext: editor.isActive("lueckentext"),
      answerBlock: editor.isActive("answerBlock"),
      table: editor.isActive("table"),
      teacherComment: editor.isActive("teacherComment"),
      highlightColor: HIGHLIGHT_COLORS.find((c) =>
        editor.isActive("highlight", { color: c.value }),
      )?.value,
      textColor: TEXT_COLORS.find((c) =>
        editor.isActive("textStyle", { color: c.value }),
      )?.value,
      calloutColor: CALLOUT_COLORS.find((c) =>
        editor.isActive("callout", { color: c.value }),
      )?.value,
      // False when the selection covers a question heading — wrapping one
      // would hide it from the server-side part splitting.
      canCallout: editor.can().setCallout(DEFAULT_CALLOUT_COLOR),
      canUndo: editor.can().undo(),
      canRedo: editor.can().redo(),
    }),
  });

  const btn = (
    title: string,
    icon: ReactNode,
    action: () => void,
    isActive = false,
    disabled = false,
  ) => (
    // Keyed by title: the group() helper receives these as a plain array.
    <Tip key={title} label={title}>
      <button
        type="button"
        aria-label={title}
        className={"exam-editor__btn" + (isActive ? " is-active" : "")}
        onMouseDown={(e) => e.preventDefault()}
        onClick={action}
        disabled={disabled}
      >
        {icon}
      </button>
    </Tip>
  );

  const iconCls = "exam-editor__icon";

  const colorMenu = ({
    title,
    icon,
    colors,
    activeColor,
    onPick,
    onClear,
    clearLabel,
    disabled = false,
  }: {
    title: string;
    icon: ReactNode;
    // `swatch` decouples the painted chip from the stored value — the callout
    // palette stores a token ("red"), not a hex colour.
    colors: Array<{ name: string; value: string; swatch?: string }>;
    activeColor?: string;
    onPick: (value: string) => void;
    onClear: () => void;
    clearLabel: string;
    disabled?: boolean;
  }) => {
    const swatchOf = (value?: string) =>
      colors.find((c) => c.value === value)?.swatch ?? value;

    return (
      <DropdownMenu.Root key={title}>
        <Tip label={title}>
          <DropdownMenu.Trigger asChild>
            <button
              type="button"
              aria-label={title}
              className={"exam-editor__btn" + (activeColor ? " is-active" : "")}
              onMouseDown={(e) => e.preventDefault()}
              disabled={disabled}
            >
              {icon}
              <span
                className="exam-editor__btn-bar"
                style={{
                  backgroundColor: swatchOf(activeColor) || "transparent",
                }}
              />
            </button>
          </DropdownMenu.Trigger>
        </Tip>
        <DropdownMenu.Portal>
          <DropdownMenu.Content
            className="exam-editor__menu"
            sideOffset={4}
            align="start"
          >
            <div className="exam-editor__menu-swatches">
              {colors.map((c) => (
                <DropdownMenu.Item
                  key={c.value}
                  asChild
                  onSelect={() => onPick(c.value)}
                >
                  <button
                    type="button"
                    title={c.name}
                    aria-label={c.name}
                    className={
                      "exam-editor__swatch" +
                      (activeColor === c.value ? " is-active" : "")
                    }
                    style={{ backgroundColor: c.swatch ?? c.value }}
                  />
                </DropdownMenu.Item>
              ))}
            </div>
            <DropdownMenu.Separator className="exam-editor__menu-separator" />
            <DropdownMenu.Item
              className="exam-editor__menu-item"
              onSelect={onClear}
            >
              {clearLabel}
            </DropdownMenu.Item>
          </DropdownMenu.Content>
        </DropdownMenu.Portal>
      </DropdownMenu.Root>
    );
  };

  const textColorMenu = colorMenu({
    title: "Textfarbe",
    icon: <TextColorIcon className={iconCls} />,
    colors: TEXT_COLORS,
    activeColor: active.textColor,
    onPick: (value) => editor.chain().focus().setColor(value).run(),
    onClear: () => editor.chain().focus().unsetColor().run(),
    clearLabel: "Farbe entfernen",
  });

  const highlightMenu = colorMenu({
    title: "Markieren",
    icon: <PaintBrushIcon className={iconCls} />,
    colors: HIGHLIGHT_COLORS,
    activeColor: active.highlightColor,
    onPick: (value) =>
      editor.chain().focus().toggleHighlight({ color: value }).run(),
    onClear: () => editor.chain().focus().unsetHighlight().run(),
    clearLabel: "Markierung entfernen",
  });

  const calloutMenu = colorMenu({
    title: "Hinweisbox",
    icon: <InformationCircleIcon className={iconCls} />,
    colors: CALLOUT_COLORS,
    activeColor: active.calloutColor,
    onPick: (value) =>
      editor
        .chain()
        .focus()
        .setCallout(value as CalloutColor)
        .run(),
    onClear: () => editor.chain().focus().unsetCallout().run(),
    clearLabel: "Hinweisbox entfernen",
    disabled: !active.canCallout,
  });

  const group = (label: string, children: ReactNode) => (
    <div className="exam-editor__group">
      <div className="exam-editor__group-btns">
        {Children.map(children, (c) => c)}
      </div>
      <span className="exam-editor__group-label">{label}</span>
    </div>
  );

  const [tab, setTab] = useState("start");

  return (
    <Tooltip.Provider delayDuration={400} skipDelayDuration={300}>
      <div className="exam-editor__toolbar">
      <Tabs.Root
        value={tab}
        onValueChange={setTab}
        className="exam-editor__tabs"
      >
        <div className="exam-editor__tabs-bar">
          <Tabs.List className="exam-editor__tabs-list">
            <Tabs.Trigger value="start" className="exam-editor__tab">
              Start
            </Tabs.Trigger>
            <Tabs.Trigger value="tabellen" className="exam-editor__tab">
              Tabellen
            </Tabs.Trigger>
            {correctionMode && (
              <Tabs.Trigger value="korrektur" className="exam-editor__tab">
                Korrektur
              </Tabs.Trigger>
            )}
          </Tabs.List>
          <StatusIndicator status={status} errorMsg={errorMsg} />
        </div>
        <Tabs.Content value="start" className="exam-editor__tab-content">
          <div className="exam-editor__toolbar-inner">
            {group("Aktionen", [
              btn(
                "Rückgängig",
                <ArrowUturnLeftIcon className={iconCls} />,
                () => editor.chain().focus().undo().run(),
                false,
                !active.canUndo,
              ),
              btn(
                "Wiederholen",
                <ArrowUturnRightIcon className={iconCls} />,
                () => editor.chain().focus().redo().run(),
                false,
                !active.canRedo,
              ),
            ])}
            {group("Schriftart", [
              btn(
                "Überschrift 1",
                <H1Icon className={iconCls} />,
                () => editor.chain().focus().toggleHeading({ level: 1 }).run(),
                active.h1,
              ),
              btn(
                "Überschrift 2",
                <H2Icon className={iconCls} />,
                () => editor.chain().focus().toggleHeading({ level: 2 }).run(),
                active.h2,
              ),
              btn(
                "Fett",
                <BoldIcon className={iconCls} />,
                () => editor.chain().focus().toggleBold().run(),
                active.bold,
              ),
              btn(
                "Unterstrichen",
                <UnderlineIcon className={iconCls} />,
                () => editor.chain().focus().toggleUnderline().run(),
                active.underline,
              ),
              btn(
                "Kursiv",
                <ItalicIcon className={iconCls} />,
                () => editor.chain().focus().toggleItalic().run(),
                active.italic,
              ),
              textColorMenu,
              highlightMenu,
            ])}
            {group("Listen", [
              btn(
                "Aufzählung",
                <ListBulletIcon className={iconCls} />,
                () => editor.chain().focus().toggleBulletList().run(),
                active.bulletList,
              ),
              btn(
                "Nummerierte Liste",
                <NumberedListIcon className={iconCls} />,
                () => editor.chain().focus().toggleOrderedList().run(),
                active.orderedList,
              ),
            ])}
            {!hideAnswers && group("Hinweisbox", [calloutMenu])}
            {!hideQuestion &&
              group("Frage", [
                btn(
                  "Frage",
                  <QuestionMarkCircleIcon className={iconCls} />,
                  () => editor.chain().focus().toggleHeading({ level: 3 }).run(),
                  active.h3,
                ),
              ])}
            {!hideAnswers &&
              group("Antworten", [
                btn(
                  "Antwortfeld",
                  <FreitextAbcIcon className={iconCls} />,
                  () => editor.chain().focus().setAnswerBlock().run(),
                  active.answerBlock,
                ),
                btn(
                  "Aufgabenliste",
                  <MultipleChoiceIcon className={iconCls} />,
                  () => editor.chain().focus().toggleTaskList().run(),
                  active.taskList,
                ),
                btn(
                  "Lückentextfeld",
                  <LueckentextIcon className={iconCls} />,
                  () => editor.chain().focus().setLueckentext().run(),
                  active.lueckentext,
                ),
              ])}
            {uploadImage &&
              group("Einfügen", [
                <ImageButton
                  key="image"
                  editor={editor}
                  uploadImage={uploadImage}
                />,
              ])}
          </div>
        </Tabs.Content>
        <Tabs.Content value="tabellen" className="exam-editor__tab-content">
          <div className="exam-editor__toolbar-inner">
            {group("Tabelle", [
              btn(
                "Tabelle einfügen",
                <TableCellsIcon className={iconCls} />,
                () =>
                  editor
                    .chain()
                    .focus()
                    .insertTable({ rows: 3, cols: 3, withHeaderRow: true })
                    .run(),
              ),
              btn(
                "Kopfzeile umschalten",
                <HeaderRowIcon className={iconCls} />,
                () => editor.chain().focus().toggleHeaderRow().run(),
                false,
                !active.table,
              ),
              btn(
                "Tabelle löschen",
                <RemoveTableIcon className={iconCls} />,
                () => editor.chain().focus().deleteTable().run(),
                false,
                !active.table,
              ),
            ])}
            {group("Zeilen", [
              btn(
                "Zeile darüber einfügen",
                <AddRowAboveIcon className={iconCls} />,
                () => editor.chain().focus().addRowBefore().run(),
                false,
                !active.table,
              ),
              btn(
                "Zeile darunter einfügen",
                <AddRowBelowIcon className={iconCls} />,
                () => editor.chain().focus().addRowAfter().run(),
                false,
                !active.table,
              ),
              btn(
                "Zeile löschen",
                <RemoveRowIcon className={iconCls} />,
                () => editor.chain().focus().deleteRow().run(),
                false,
                !active.table,
              ),
            ])}
            {group("Spalten", [
              btn(
                "Spalte davor einfügen",
                <AddColumnLeftIcon className={iconCls} />,
                () => editor.chain().focus().addColumnBefore().run(),
                false,
                !active.table,
              ),
              btn(
                "Spalte danach einfügen",
                <AddColumnRightIcon className={iconCls} />,
                () => editor.chain().focus().addColumnAfter().run(),
                false,
                !active.table,
              ),
              btn(
                "Spalte löschen",
                <RemoveColumnIcon className={iconCls} />,
                () => editor.chain().focus().deleteColumn().run(),
                false,
                !active.table,
              ),
            ])}
          </div>
        </Tabs.Content>
        {correctionMode && (
          <Tabs.Content value="korrektur" className="exam-editor__tab-content">
            <div className="exam-editor__toolbar-inner">
              {group("Anmerkungen", [
                btn(
                  "Lehrerkommentar",
                  <ChatBubbleLeftEllipsisIcon className={iconCls} />,
                  () => editor.chain().focus().toggleTeacherComment().run(),
                  active.teacherComment,
                ),
              ])}
              {group("Bewertung", [
                btn(
                  "Falsch",
                  <span className="exam-editor__emoji" aria-hidden="true">
                    ❌
                  </span>,
                  () => editor.chain().focus().insertContent("❌").run(),
                ),
                btn(
                  "Richtig",
                  <span className="exam-editor__emoji" aria-hidden="true">
                    ✅
                  </span>,
                  () => editor.chain().focus().insertContent("✅").run(),
                ),
              ])}
            </div>
          </Tabs.Content>
        )}
      </Tabs.Root>
      {lockHintEnabled && (
        <div
          className={
            "exam-editor__lock-hint" + (lockHintVisible ? " is-visible" : "")
          }
          role="status"
          aria-live="polite"
        >
          {lockHintVisible ? lockHintText : ""}
        </div>
      )}
      </div>
    </Tooltip.Provider>
  );
}

const IS_MAC =
  typeof navigator !== "undefined" &&
  /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent || "");

// Keyboard shortcuts shown in tooltips. These mirror the Tiptap / StarterKit
// defaults for the corresponding commands.
const SHORTCUTS = {
  Rückgängig: "Mod-Z",
  Wiederholen: "Mod-Shift-Z",
  "Überschrift 1": "Mod-Alt-1",
  "Überschrift 2": "Mod-Alt-2",
  Fett: "Mod-B",
  Kursiv: "Mod-I",
  Markieren: "Mod-Shift-H",
  Aufzählung: "Mod-Shift-8",
  "Nummerierte Liste": "Mod-Shift-7",
  Frage: "Mod-Alt-3",
  Aufgabenliste: "Mod-Shift-9",
};

function formatShortcut(combo: string | undefined) {
  if (!combo) return null;
  return combo
    .split("-")
    .map((part) => {
      if (part === "Mod") return IS_MAC ? "⌘" : "Ctrl";
      if (part === "Shift") return IS_MAC ? "⇧" : "Shift";
      if (part === "Alt") return IS_MAC ? "⌥" : "Alt";
      return part.toUpperCase();
    })
    .join(IS_MAC ? "" : "+");
}

function ImageButton({ editor, uploadImage }: { editor: Editor; uploadImage: (file: File) => Promise<{ url: string }> }) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);

  const onPick = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = ""; // allow re-picking the same file
    if (!file) return;
    setUploading(true);
    try {
      const { url } = await uploadImage(file);
      editor.chain().focus().setImage({ src: url }).run();
    } catch (err) {
      console.error("Bild-Upload fehlgeschlagen", err);
      window.alert((err as Error).message || "Bild-Upload fehlgeschlagen");
    } finally {
      setUploading(false);
    }
  };

  return (
    <>
      <Tip label="Bild einfügen">
        <button
          type="button"
          aria-label="Bild einfügen"
          className="exam-editor__btn"
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => inputRef.current?.click()}
          disabled={uploading}
        >
          <PhotoIcon className="exam-editor__icon" />
        </button>
      </Tip>
      <input
        ref={inputRef}
        type="file"
        accept="image/png,image/jpeg,image/gif,image/webp"
        style={{ display: "none" }}
        onChange={onPick}
      />
    </>
  );
}

function Tip({ label, children }: { label: string; children: ReactNode }) {
  const shortcut = formatShortcut(SHORTCUTS[label as keyof typeof SHORTCUTS]);
  return (
    <Tooltip.Root>
      <Tooltip.Trigger asChild>{children}</Tooltip.Trigger>
      <Tooltip.Portal>
        <Tooltip.Content
          className="exam-editor__tooltip"
          side="bottom"
          sideOffset={6}
        >
          {label}
          {shortcut && <span className="exam-editor__tooltip-kbd">{shortcut}</span>}
          <Tooltip.Arrow className="exam-editor__tooltip-arrow" />
        </Tooltip.Content>
      </Tooltip.Portal>
    </Tooltip.Root>
  );
}

export function StatusIndicator({ status, errorMsg }: { status: string; errorMsg?: string | null }) {
  if (status !== "error") return null;
  return (
    <div className="exam-editor__status exam-editor__status--error" role="alert">
      <span className="exam-editor__status-label">
        {errorMsg || "Fehler beim Speichern"}
      </span>
    </div>
  );
}
