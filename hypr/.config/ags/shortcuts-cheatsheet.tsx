import { Accessor, createState } from "ags"
import app from "ags/gtk4/app"
import { Astal } from "ags/gtk4"
import GLib from "gi://GLib"
import Gdk from "gi://Gdk"
import Gtk from "gi://Gtk"

import css from "./shortcuts-cheatsheet.css"
import {
  SHORTCUT_TABS,
  type Section,
  type Shortcut,
  type ShortcutTab,
} from "./shortcuts-data"

const monitor =
  Number.parseInt(GLib.getenv("AGS_SHORTCUTS_MONITOR") || "0", 10) || 0

function hideWindow() {
  const win = app.get_window("shortcuts-cheatsheet")
  if (win) win.visible = false
}

function keyGroups(keys: string): string[][] {
  return keys
    .split(/\s*\/\s*/)
    .map((group) => group.trim().split(/\s+/).filter(Boolean))
    .filter((group) => group.length > 0)
}

function matchesShortcut(item: Shortcut, query: string) {
  if (!query) return true
  const hay = `${item.keys} ${item.desc}`.toLowerCase()
  return hay.includes(query.toLowerCase())
}

function Keycaps(props: { keys: string }) {
  const groups = keyGroups(props.keys)
  return (
    <box class="keycaps-row" orientation={Gtk.Orientation.HORIZONTAL}>
      {groups.map((parts, gi) => (
        <box orientation={Gtk.Orientation.HORIZONTAL}>
          {gi > 0 ? <label class="keycap-sep" label="/" /> : null}
          {parts.map((part) => (
            <label class="keycap" label={part} />
          ))}
        </box>
      ))}
    </box>
  )
}

function ShortcutRow(props: { item: Shortcut; query: Accessor<string> }) {
  return (
    <box
      class="shortcut-row"
      visible={props.query((q) => matchesShortcut(props.item, q.trim()))}
    >
      <label class="shortcut-desc" xalign={0} hexpand label={props.item.desc} />
      <Keycaps keys={props.item.keys} />
    </box>
  )
}

function SectionBlock(props: { section: Section; query: Accessor<string> }) {
  const hasItems = props.query((q) =>
    props.section.items.some((item) => matchesShortcut(item, q.trim())),
  )
  return (
    <box
      class="section"
      orientation={Gtk.Orientation.VERTICAL}
      visible={hasItems}
    >
      <label class="section-title" xalign={0} label={props.section.title} />
      {props.section.items.map((item) => (
        <ShortcutRow item={item} query={props.query} />
      ))}
    </box>
  )
}

function splitColumns(sections: Section[]) {
  const mid = Math.ceil(sections.length / 2)
  return [sections.slice(0, mid), sections.slice(mid)]
}

function TabContent(props: { tab: ShortcutTab; query: Accessor<string> }) {
  const [left, right] = splitColumns(props.tab.sections)
  return (
    <box class="shortcuts-columns">
      <box class="shortcuts-column" orientation={Gtk.Orientation.VERTICAL} hexpand>
        {left.map((section) => (
          <SectionBlock section={section} query={props.query} />
        ))}
      </box>
      <box class="shortcuts-column" orientation={Gtk.Orientation.VERTICAL} hexpand>
        {right.map((section) => (
          <SectionBlock section={section} query={props.query} />
        ))}
      </box>
    </box>
  )
}

function ShortcutsCheatsheet() {
  const [activeTab, setActiveTab] = createState(SHORTCUT_TABS[0].id)
  const [query, setQuery] = createState("")

  let searchEntry: Gtk.Entry | null = null

  function bindSearchEntry(entry: Gtk.Entry) {
    searchEntry = entry
    entry.connect("changed", () => setQuery(entry.text ?? ""))
    const win = app.get_window("shortcuts-cheatsheet")
    win?.connect("notify::visible", () => {
      if (win.visible) {
        GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
          searchEntry?.grab_focus()
          return GLib.SOURCE_REMOVE
        })
      }
    })
  }

  const anchor =
    Astal.WindowAnchor.TOP |
    Astal.WindowAnchor.RIGHT |
    Astal.WindowAnchor.BOTTOM |
    Astal.WindowAnchor.LEFT

  let dismissReady = false
  GLib.idle_add(GLib.PRIORITY_LOW, () => {
    dismissReady = true
    return GLib.SOURCE_REMOVE
  })

  return (
    <window
      name="shortcuts-cheatsheet"
      application={app}
      visible={false}
      class="ShortcutsWindow"
      namespace="shortcuts-cheatsheet"
      monitor={monitor}
      anchor={anchor}
      keymode={Astal.Keymode.ON_DEMAND}
    >
      <box hexpand vexpand>
        <Gtk.EventControllerKey
          onKeyPressed={(_: unknown, keyval: number) => {
            if (keyval === Gdk.KEY_Escape) hideWindow()
          }}
        />
        <Gtk.GestureClick
          onPressed={(_: unknown, _n: number, x: number, y: number) => {
            if (!dismissReady) return
            const w = (_ as Gtk.GestureClick).get_widget() as Gtk.Widget
            const root = w?.get_last_child()
            const picked = w?.pick(x, y, Gtk.PickFlags.DEFAULT)
            const onPanel =
              root &&
              picked !== null &&
              (picked === root || picked.is_ancestor(root))
            if (!onPanel) hideWindow()
          }}
        />
        <box
          class="shortcuts-root"
          halign={Gtk.Align.CENTER}
          valign={Gtk.Align.CENTER}
          hexpand
          vexpand
        >
          <box class="shortcuts-panel" orientation={Gtk.Orientation.VERTICAL}>
            <box class="shortcuts-header" orientation={Gtk.Orientation.VERTICAL}>
              <box class="search-row" orientation={Gtk.Orientation.HORIZONTAL}>
                <label class="search-icon" label="⌕" />
                <entry
                  class="search-entry"
                  hexpand
                  placeholder-text="Search keybindings..."
                  $={(entry: Gtk.Entry) => bindSearchEntry(entry)}
                />
                <button class="shortcuts-close" onClicked={hideWindow}>
                  <label label="✕" />
                </button>
              </box>

              <box class="shortcuts-tabs">
                {SHORTCUT_TABS.map((tab) => (
                  <button
                    class={activeTab((id) =>
                      id === tab.id ? "filter-chip active" : "filter-chip",
                    )}
                    onClicked={() => setActiveTab(tab.id)}
                  >
                    <label label={tab.label} />
                  </button>
                ))}
              </box>
            </box>

            <scrolledwindow
              class="shortcuts-scroll"
              hscrollbar-policy={Gtk.PolicyType.NEVER}
              vscrollbar-policy={Gtk.PolicyType.AUTOMATIC}
              hexpand
              vexpand
            >
              <box class="shortcuts-content" orientation={Gtk.Orientation.VERTICAL}>
                {SHORTCUT_TABS.map((tab) => (
                  <box
                    visible={activeTab((id) => id === tab.id)}
                    orientation={Gtk.Orientation.VERTICAL}
                  >
                    <TabContent tab={tab} query={query} />
                  </box>
                ))}
              </box>
            </scrolledwindow>

            <box class="shortcuts-footer">
              <label
                class="shortcuts-hint"
                xalign={0}
                hexpand
                label="Esc to close · Super Shift + ? to toggle"
              />
            </box>
          </box>
        </box>
      </box>
    </window>
  )
}

app.start({
  css,
  instanceName: "shortcuts-cheatsheet",
  main() {
    return <ShortcutsCheatsheet />
  },
})
