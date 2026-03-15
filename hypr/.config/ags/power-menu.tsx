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
  const anchor = Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT

  return (
    <window
      visible
      class="PowerMenuWindow"
      namespace="power-menu"
      monitor={monitor}
      anchor={anchor}
      keymode={Astal.Keymode.NONE}
    >
      <box class="PowerMenuRoot">
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
