import { createState } from "ags"
import app from "ags/gtk4/app"
import { Astal } from "ags/gtk4"
import GLib from "gi://GLib"
import Gtk from "gi://Gtk"

import css from "./style.css"

type AudioNode = {
  id: string
  description?: string
  name?: string
  title?: string
  percent: number
  muted: boolean
}

type AudioState = {
  sink: AudioNode | null
  source: AudioNode | null
  streams: AudioNode[]
}

const HOME = GLib.get_home_dir()
const dataScript = `${HOME}/.config/waybar/scripts/volume-popup-data.sh`
const controlScript = `${HOME}/.config/waybar/scripts/volume-popup-control.sh`
const monitor =
  Number.parseInt(GLib.getenv("AGS_VOLUME_MONITOR") || "0", 10) || 0

function sq(v: string) {
  return `'${v.replace(/'/g, `'\\''`)}'`
}

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

function readAudio(): AudioState {
  try {
    return JSON.parse(run(sq(dataScript)))
  } catch {
    return { sink: null, source: null, streams: [] }
  }
}

function setVol(target: string, id: string, value: number) {
  const pct = Math.max(0, Math.min(150, Math.round(value)))
  runAsync(`${sq(controlScript)} set ${target} ${sq(id)} ${pct}`)
}

function toggleMute(target: string, id: string) {
  runAsync(`${sq(controlScript)} toggle-mute ${target} ${sq(id)}`)
}

function dismiss() {
  app.quit()
}

function MixerWindow() {
  const [sinkVol, setSinkVol] = createState(0)
  const [sinkMuted, setSinkMuted] = createState(false)
  const [sinkDesc, setSinkDesc] = createState("Output")
  const [hasSink, setHasSink] = createState(false)

  const [srcVol, setSrcVol] = createState(0)
  const [srcMuted, setSrcMuted] = createState(false)
  const [srcDesc, setSrcDesc] = createState("Microphone")
  const [hasSrc, setHasSrc] = createState(false)

  const [appVol, setAppVol] = createState(0)
  const [appMuted, setAppMuted] = createState(false)
  const [appName, setAppName] = createState("")
  const [hasApp, setHasApp] = createState(false)

  let sinkId = ""
  let srcId = ""
  let appId = ""
  let sinkMutedVal = false
  let srcMutedVal = false
  let appMutedVal = false

  let drag: string | null = null
  let dragTimer = 0

  function beginDrag(t: string) {
    drag = t
    if (dragTimer) {
      GLib.source_remove(dragTimer)
      dragTimer = 0
    }
  }

  function endDrag() {
    if (dragTimer) GLib.source_remove(dragTimer)
    dragTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1500, () => {
      drag = null
      dragTimer = 0
      return GLib.SOURCE_REMOVE
    })
  }

  function poll() {
    const s = readAudio()

    if (s.sink) {
      sinkId = s.sink.id
      setHasSink(true)
      setSinkDesc(s.sink.description || "Output")
      if (drag !== "sink") {
        setSinkVol(s.sink.percent)
        sinkMutedVal = s.sink.muted
        setSinkMuted(s.sink.muted)
      }
    } else {
      setHasSink(false)
    }

    if (s.source) {
      srcId = s.source.id
      setHasSrc(true)
      setSrcDesc(s.source.description || "Microphone")
      if (drag !== "source") {
        setSrcVol(s.source.percent)
        srcMutedVal = s.source.muted
        setSrcMuted(s.source.muted)
      }
    } else {
      setHasSrc(false)
    }

    const st =
      s.streams.find((x) => x.name?.toLowerCase() === "spotify") ||
      s.streams[0]
    if (st) {
      appId = st.id
      setHasApp(true)
      setAppName(
        st.title && st.title !== st.name
          ? `${st.name} — ${st.title}`
          : st.name || "App",
      )
      if (drag !== "stream") {
        setAppVol(st.percent)
        appMutedVal = st.muted
        setAppMuted(st.muted)
      }
    } else {
      setHasApp(false)
    }
  }

  poll()
  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, () => {
    poll()
    return GLib.SOURCE_CONTINUE
  })

  let db1 = 0
  let db2 = 0
  let db3 = 0

  function onSinkSlide(v: number) {
    const r = Math.round(v)
    beginDrag("sink")
    setSinkVol(r)
    if (db1) GLib.source_remove(db1)
    db1 = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, () => {
      setVol("sink", sinkId, r)
      endDrag()
      db1 = 0
      return GLib.SOURCE_REMOVE
    })
  }

  function onSrcSlide(v: number) {
    const r = Math.round(v)
    beginDrag("source")
    setSrcVol(r)
    if (db2) GLib.source_remove(db2)
    db2 = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, () => {
      setVol("source", srcId, r)
      endDrag()
      db2 = 0
      return GLib.SOURCE_REMOVE
    })
  }

  function onAppSlide(v: number) {
    const r = Math.round(v)
    beginDrag("stream")
    setAppVol(r)
    if (db3) GLib.source_remove(db3)
    db3 = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, () => {
      setVol("stream", appId, r)
      endDrag()
      db3 = 0
      return GLib.SOURCE_REMOVE
    })
  }

  let canDismiss = false
  GLib.idle_add(GLib.PRIORITY_LOW, () => {
    canDismiss = true
    return GLib.SOURCE_REMOVE
  })

  const [opacity, setOpacity] = createState(0)
  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 120, () => {
    setOpacity(1)
    return GLib.SOURCE_REMOVE
  })

  const anchor =
    Astal.WindowAnchor.TOP |
    Astal.WindowAnchor.RIGHT |
    Astal.WindowAnchor.BOTTOM |
    Astal.WindowAnchor.LEFT

  return (
    <window
      visible
      opacity={opacity}
      class="VolumeWindow"
      namespace="volume-popup"
      monitor={monitor}
      anchor={anchor}
      keymode={Astal.Keymode.ON_DEMAND}
    >
      <box hexpand vexpand>
        <Gtk.GestureClick
          onPressed={(_: unknown, _n: number, x: number, y: number) => {
            if (!canDismiss) return
            const w = (_ as Gtk.GestureClick).get_widget() as Gtk.Widget
            const panel = w?.get_first_child()
            const picked = w?.pick(x, y, Gtk.PickFlags.DEFAULT)
            const onPanel =
              panel &&
              picked !== null &&
              (picked === panel || picked.is_ancestor(panel))
            if (!onPanel) dismiss()
          }}
        />
        <box
          class="vol-root"
          halign={Gtk.Align.END}
          valign={Gtk.Align.START}
        >
          <box class="vol-panel" orientation={Gtk.Orientation.VERTICAL}>

            <box class="vol-titlebar">
              <label class="vol-title" xalign={0} hexpand label="Volume" />
              <button class="close-btn" onClicked={dismiss}>
                <label label="✕" />
              </button>
            </box>

            <box
              class="vol-section"
              orientation={Gtk.Orientation.VERTICAL}
              visible={hasSink}
            >
              <label class="section-label" xalign={0} label="OUTPUT" />
              <box class="slider-row" orientation={Gtk.Orientation.VERTICAL}>
                <box class="slider-header">
                  <button
                    class="mute-btn"
                    onClicked={() => {
                      toggleMute("sink", sinkId)
                      sinkMutedVal = !sinkMutedVal
                      setSinkMuted(sinkMutedVal)
                    }}
                  >
                    <label label={sinkMuted((m) => (m ? "󰝟" : "󰕾"))} />
                  </button>
                  <label
                    class="slider-label"
                    xalign={0}
                    hexpand
                    label={sinkDesc}
                  />
                  <label
                    class="slider-value"
                    label={sinkVol((v) => `${v}%`)}
                  />
                </box>
                <slider
                  class="vol-slider"
                  hexpand
                  min={0}
                  max={150}
                  value={sinkVol}
                  onChangeValue={({ value }) => onSinkSlide(value)}
                />
              </box>
            </box>

            <box
              class="vol-section"
              orientation={Gtk.Orientation.VERTICAL}
              visible={hasSrc}
            >
              <label class="section-label" xalign={0} label="MICROPHONE" />
              <box class="slider-row" orientation={Gtk.Orientation.VERTICAL}>
                <box class="slider-header">
                  <button
                    class="mute-btn"
                    onClicked={() => {
                      toggleMute("source", srcId)
                      srcMutedVal = !srcMutedVal
                      setSrcMuted(srcMutedVal)
                    }}
                  >
                    <label label={srcMuted((m) => (m ? "󰍭" : "󰍬"))} />
                  </button>
                  <label
                    class="slider-label"
                    xalign={0}
                    hexpand
                    label={srcDesc}
                  />
                  <label
                    class="slider-value"
                    label={srcVol((v) => `${v}%`)}
                  />
                </box>
                <slider
                  class="vol-slider"
                  hexpand
                  min={0}
                  max={150}
                  value={srcVol}
                  onChangeValue={({ value }) => onSrcSlide(value)}
                />
              </box>
            </box>

            <box
              class="vol-section"
              orientation={Gtk.Orientation.VERTICAL}
              visible={hasApp}
            >
              <label class="section-label" xalign={0} label="NOW PLAYING" />
              <box class="slider-row" orientation={Gtk.Orientation.VERTICAL}>
                <box class="slider-header">
                  <button
                    class="mute-btn"
                    onClicked={() => {
                      toggleMute("stream", appId)
                      appMutedVal = !appMutedVal
                      setAppMuted(appMutedVal)
                    }}
                  >
                    <label label={appMuted((m) => (m ? "󰝟" : "󰎆"))} />
                  </button>
                  <label
                    class="slider-label"
                    xalign={0}
                    hexpand
                    label={appName}
                  />
                  <label
                    class="slider-value"
                    label={appVol((v) => `${v}%`)}
                  />
                </box>
                <slider
                  class="vol-slider"
                  hexpand
                  min={0}
                  max={150}
                  value={appVol}
                  onChangeValue={({ value }) => onAppSlide(value)}
                />
              </box>
            </box>

            <button class="mixer-btn" onClicked={() => runAsync("pavucontrol")}>
              <label label="Open Mixer" />
            </button>
          </box>
        </box>
      </box>
    </window>
  )
}

app.start({
  css,
  main() {
    return <MixerWindow />
  },
})
