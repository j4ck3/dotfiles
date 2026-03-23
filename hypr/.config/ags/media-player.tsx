import { createState } from "ags"
import app from "ags/gtk4/app"
import { Astal } from "ags/gtk4"
import GLib from "gi://GLib"
import Gdk from "gi://Gdk"
import Gtk from "gi://Gtk"

import css from "./media-player.css"

const PLAYER = "spotify"
const monitor =
  Number.parseInt(GLib.getenv("AGS_MEDIA_MONITOR") || "0", 10) || 0

function run(cmd: string): string {
  try {
    const [ok, out, , status] = GLib.spawn_command_line_sync(cmd)
    if (!ok || status !== 0) return ""
    return new TextDecoder().decode(out).trim()
  } catch {
    return ""
  }
}

function runAsync(cmd: string) {
  try {
    GLib.spawn_command_line_async(cmd)
  } catch {}
}

function fmt(secs: number): string {
  const s = Math.max(0, Math.floor(secs))
  return `${Math.floor(s / 60)}:${(s % 60).toString().padStart(2, "0")}`
}

function hashUrl(s: string): number {
  let h = 0
  for (let i = 0; i < s.length; i++)
    h = ((h << 5) - h + s.charCodeAt(i)) | 0
  return Math.abs(h)
}

function downloadArt(url: string): string {
  if (!url) return ""
  if (url.startsWith("file://")) return url.slice(7)
  const dest = `/tmp/ags-media-art-${hashUrl(url)}.jpg`
  if (!GLib.file_test(dest, GLib.FileTest.EXISTS)) {
    run(`curl -sL -o '${dest}' '${url}'`)
  }
  return dest
}

function ctl(action: string) {
  runAsync(`playerctl --player=${PLAYER} ${action}`)
}

const artCssProvider = new Gtk.CssProvider()

function updateArtCss(path: string) {
  try {
    if (path && GLib.file_test(path, GLib.FileTest.EXISTS)) {
      artCssProvider.load_from_string(
        `.art-bg { background-image: url("file://${path}"); background-size: cover; background-position: center; }`,
      )
    } else {
      artCssProvider.load_from_string(`.art-bg { }`)
    }
  } catch {}
}

function MediaPlayer() {
  const display = Gdk.Display.get_default()
  if (display) {
    Gtk.StyleContext.add_provider_for_display(
      display,
      artCssProvider,
      Gtk.STYLE_PROVIDER_PRIORITY_USER,
    )
  }

  const [title, setTitle] = createState("Nothing Playing")
  const [artist, setArtist] = createState("")
  const [pos, setPos] = createState(0)
  const [len, setLen] = createState(1)
  const [playing, setPlaying] = createState(false)
  const [mediaVol, setMediaVol] = createState(50)

  let lastArtUrl = ""
  let currentLen = 1
  let seeking = false
  let seekTimer = 0
  let seekDb = 0
  let volDb = 0

  function poll() {
    const status = run(`playerctl --player=${PLAYER} status`)
    const active = status === "Playing" || status === "Paused"
    setPlaying(status === "Playing")

    if (!active) {
      setTitle("Nothing Playing")
      setArtist("")
      return
    }

    setTitle(
      run(
        `playerctl --player=${PLAYER} metadata --format '{{ title }}'`,
      ) || "Unknown",
    )
    setArtist(
      run(
        `playerctl --player=${PLAYER} metadata --format '{{ artist }}'`,
      ) || "Unknown Artist",
    )

    const artUrl = run(
      `playerctl --player=${PLAYER} metadata --format '{{ mpris:artUrl }}'`,
    )
    if (artUrl && artUrl !== lastArtUrl) {
      lastArtUrl = artUrl
      const path = downloadArt(artUrl)
      updateArtCss(path)
    }

    const us = parseInt(
      run(
        `playerctl --player=${PLAYER} metadata --format '{{ mpris:length }}'`,
      ) || "0",
    )
    currentLen = Math.max(1, us / 1_000_000)
    setLen(currentLen)

    if (!seeking) {
      setPos(
        parseFloat(run(`playerctl --player=${PLAYER} position`) || "0"),
      )
    }

    const vol = parseFloat(
      run(`playerctl --player=${PLAYER} volume`) || "0.5",
    )
    setMediaVol(Math.round(vol * 100))
  }

  poll()
  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, () => {
    poll()
    return GLib.SOURCE_CONTINUE
  })

  function onSeek(v: number) {
    seeking = true
    setPos(v)
    if (seekTimer) GLib.source_remove(seekTimer)
    if (seekDb) GLib.source_remove(seekDb)
    seekDb = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 100, () => {
      ctl(`position ${v.toFixed(1)}`)
      seekDb = 0
      seekTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1500, () => {
        seeking = false
        seekTimer = 0
        return GLib.SOURCE_REMOVE
      })
      return GLib.SOURCE_REMOVE
    })
  }

  function onVol(v: number) {
    const r = Math.round(v)
    setMediaVol(r)
    if (volDb) GLib.source_remove(volDb)
    volDb = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, () => {
      ctl(`volume ${(r / 100).toFixed(2)}`)
      volDb = 0
      return GLib.SOURCE_REMOVE
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

  const [opacity, setOpacity] = createState(0)
  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 120, () => {
    setOpacity(1)
    return GLib.SOURCE_REMOVE
  })

  return (
    <window
      visible
      opacity={opacity}
      class="MediaWindow"
      namespace="media-player"
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
          class="media-root"
          halign={Gtk.Align.END}
          valign={Gtk.Align.START}
        >
          <box class="media-panel" orientation={Gtk.Orientation.VERTICAL}>
          <box
            class="art-frame art-bg"
            widthRequest={300}
            heightRequest={300}
          />

          <label class="song-title" xalign={0} label={title} />
          <label class="song-artist" xalign={0} label={artist} />

          <slider
            class="progress-bar"
            hexpand
            min={0}
            max={len}
            value={pos}
            onChangeValue={({ value }) => onSeek(value)}
          />

          <box class="time-row">
            <label
              class="time-label"
              xalign={0}
              hexpand
              label={pos((p) => fmt(p))}
            />
            <label
              class="time-label"
              xalign={1}
              label={pos((p) => `-${fmt(currentLen - p)}`)}
            />
          </box>

          <box class="transport" halign={Gtk.Align.CENTER}>
            <button class="transport-btn" onClicked={() => ctl("previous")}>
              <label class="transport-icon" label="󰒮" />
            </button>
            <button class="play-btn" onClicked={() => ctl("play-pause")}>
              <label
                class="play-icon"
                label={playing((p) => (p ? "󰏤" : "󰐊"))}
              />
            </button>
            <button class="transport-btn" onClicked={() => ctl("next")}>
              <label class="transport-icon" label="󰒭" />
            </button>
          </box>

          <box class="media-vol-row">
            <label class="media-vol-icon" label="󰕿" />
            <slider
              class="media-vol-slider"
              hexpand
              min={0}
              max={100}
              value={mediaVol}
              onChangeValue={({ value }) => onVol(value)}
            />
            <label class="media-vol-icon" label="󰕾" />
          </box>
          </box>
        </box>
      </box>
    </window>
  )
}

app.start({
  css,
  instanceName: "media-player",
  main() {
    return <MediaPlayer />
  },
})
