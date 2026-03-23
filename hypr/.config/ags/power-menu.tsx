import { createState } from "ags"
import app from "ags/gtk4/app"
import { Astal } from "ags/gtk4"
import GLib from "gi://GLib"
import Gtk from "gi://Gtk"

import css from "./power-menu.css"

const monitor =
  Number.parseInt(GLib.getenv("AGS_POWER_MONITOR") || "0", 10) || 0

function powerAction(command: string) {
  GLib.spawn_command_line_async(command)
  app.quit()
}

function PowerButton(props: {
  icon: string
  label: string
  action: () => void
  className?: string
}) {
  return (
    <button
      class={`power-button ${props.className || ""}`}
      onClicked={props.action}
    >
      <box>
        <label class="power-icon" label={props.icon} />
        <label class="power-label" hexpand xalign={0} label={props.label} />
      </box>
    </button>
  )
}

function PowerMenu() {
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

  const [opacity, setOpacity] = createState(0)
  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 120, () => {
    setOpacity(1)
    return GLib.SOURCE_REMOVE
  })

  return (
    <window
      visible
      opacity={opacity}
      class="PowerMenuWindow"
      namespace="power-menu"
      monitor={monitor}
      anchor={anchor}
      keymode={Astal.Keymode.ON_DEMAND}
    >
      <box hexpand vexpand>
        <Gtk.GestureClick
          onPressed={(_: unknown, _n: number, x: number, y: number) => {
            if (!dismissReady) return
            const w = (_ as Gtk.GestureClick).get_widget() as Gtk.Widget
            const panel = w?.get_first_child()
            const picked = w?.pick(x, y, Gtk.PickFlags.DEFAULT)
            const onPanel =
              panel &&
              picked !== null &&
              (picked === panel || picked.is_ancestor(panel))
            if (!onPanel) app.quit()
          }}
        />
        <box
          class="PowerMenuRoot"
          halign={Gtk.Align.END}
          valign={Gtk.Align.START}
        >
          <box class="PowerMenuPanel" orientation={Gtk.Orientation.VERTICAL}>
            <box class="panel-titlebar">
            <label class="panel-title" xalign={0} hexpand label="Power" />
            <button class="close-button" onClicked={() => app.quit()}>
              <label label="Close" />
            </button>
          </box>

          <box class="power-list" orientation={Gtk.Orientation.VERTICAL}>
            <PowerButton
              icon="󰌾"
              label="Lock Screen"
              action={() => powerAction("loginctl lock-session")}
            />
            <PowerButton
              icon="󰤄"
              label="Suspend"
              action={() => powerAction("systemctl suspend")}
            />
            <PowerButton
              icon="󰜉"
              label="Reboot"
              action={() => powerAction("systemctl reboot")}
            />
            <PowerButton
              icon="󰐥"
              label="Shut Down"
              className="shutdown"
              action={() => powerAction("systemctl poweroff")}
            />
            <PowerButton
              icon="󰍃"
              label="Log Out"
              action={() => powerAction("hyprctl dispatch exit")}
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
  instanceName: "power-menu",
  main() {
    return <PowerMenu />
  },
})
