import { createState, With } from "ags"
import app from "ags/gtk4/app"
import { Astal } from "ags/gtk4"
import { createPoll } from "ags/time"
import GLib from "gi://GLib"
import Gtk from "gi://Gtk"

import css from "./style.css"

type SliderTarget = "sink" | "source" | "stream"

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

const initialState: AudioState = {
  sink: null,
  source: null,
  streams: [],
}

const dataScript = `${GLib.get_home_dir()}/.config/waybar/scripts/volume-popup-data.sh`
const controlScript = `${GLib.get_home_dir()}/.config/waybar/scripts/volume-popup-control.sh`
const monitor = Number.parseInt(GLib.getenv("AGS_VOLUME_MONITOR") || "0", 10) || 0

function shellQuote(value: string) {
  return `'${value.replace(/'/g, `'\\''`)}'`
}

function runCommand(command: string) {
  const [ok, stdout, stderr, status] = GLib.spawn_command_line_sync(command)
  if (!ok || status !== 0) {
    const message = new TextDecoder().decode(stderr).trim() || `command failed: ${command}`
    throw new Error(message)
  }

  return new TextDecoder().decode(stdout).trim()
}

function runCommandAsync(command: string) {
  try {
    GLib.spawn_command_line_async(command)
  } catch (error) {
    printerr(`async command error: ${error}`)
  }
}

function readAudioState() {
  try {
    const output = runCommand(shellQuote(dataScript))
    return JSON.parse(output) as AudioState
  } catch (error) {
    printerr(`volume popup data error: ${error}`)
    return initialState
  }
}

function setVolume(target: SliderTarget, id: string, value: number) {
  const pct = Math.max(0, Math.min(150, Math.round(value)))
  runCommandAsync(
    `${shellQuote(controlScript)} set ${target} ${shellQuote(id)} ${pct}`,
  )
}

function toggleMute(target: SliderTarget, id: string) {
  runCommandAsync(
    `${shellQuote(controlScript)} toggle-mute ${target} ${shellQuote(id)}`,
  )
}

function openFullMixer() {
  runCommandAsync("pavucontrol >/dev/null 2>&1 &")
}

function sectionTitle(label: string) {
  return <label class="section-title" xalign={0} label={label} />
}

function SliderRow(props: {
  icon: string
  label: string
  value: number
  muted: boolean
  onMute: () => void
  onChange: (value: number) => void
}) {
  const [currentValue, setCurrentValue] = createState(props.value)
  const [currentMuted, setCurrentMuted] = createState(props.muted)
  let debounceId = 0

  function handleMute() {
    props.onMute()
    setCurrentMuted((value) => !value)
  }

  function handleChange(value: number) {
    const rounded = Math.round(value)
    setCurrentValue(rounded)

    if (debounceId !== 0) {
      GLib.source_remove(debounceId)
    }

    debounceId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 60, () => {
      props.onChange(rounded)
      debounceId = 0
      return GLib.SOURCE_REMOVE
    })
  }

  return (
    <box class="slider-row" orientation={Gtk.Orientation.VERTICAL}>
      <box class="slider-header">
        <button class="mute-button" onClicked={handleMute}>
          <label label={currentMuted((muted) => (muted ? "󰝟" : props.icon))} />
        </button>
        <label class="slider-label" xalign={0} hexpand label={props.label} />
        <label class="slider-value" label={currentValue((value) => `${Math.round(value)}%`)} />
      </box>
      <slider
        class="volume-slider"
        hexpand
        min={0}
        max={150}
        value={currentValue}
        onChangeValue={({ value }) => handleChange(value)}
      />
    </box>
  )
}

function MixerWindow() {
  const audio = createPoll<AudioState>(initialState, 1000, readAudioState)
  const anchor = Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT
  const sink = audio((state) => state.sink)
  const source = audio((state) => state.source)
  const streams = audio((state) => state.streams)
  const activeApp = audio(
    (state) =>
      state.streams.find((stream) => stream.name?.toLowerCase() === "spotify")
      || state.streams[0]
      || null,
  )

  return (
    <window
      visible
      class="VolumePopupWindow"
      namespace="volume-popup"
      monitor={monitor}
      anchor={anchor}
      keymode={Astal.Keymode.NONE}
    >
      <box class="VolumePopupRoot">
        <box class="VolumePopupPanel" orientation={Gtk.Orientation.VERTICAL}>
          <box class="panel-titlebar">
            <label class="panel-title" xalign={0} hexpand label="Audio Mixer" />
            <button class="close-button" onClicked={() => app.quit()}>
              <label label="Close" />
            </button>
          </box>

          <box class="section" orientation={Gtk.Orientation.VERTICAL}>
            {sectionTitle("Output")}
            <With value={sink}>
              {(sink) =>
                sink ? (
                  <SliderRow
                    icon="󰕾"
                    label={sink.description || "Default sink"}
                    value={sink.percent}
                    muted={sink.muted}
                    onMute={() => toggleMute("sink", sink.id)}
                    onChange={(value) => setVolume("sink", sink.id, value)}
                  />
                ) : (
                  <label class="empty-state" xalign={0} label="No output device found." />
                )
              }
            </With>
          </box>

          <box class="section" orientation={Gtk.Orientation.VERTICAL}>
            {sectionTitle("Microphone")}
            <With value={source}>
              {(source) =>
                source ? (
                  <SliderRow
                    icon="󰍬"
                    label={source.description || "Default source"}
                    value={source.percent}
                    muted={source.muted}
                    onMute={() => toggleMute("source", source.id)}
                    onChange={(value) => setVolume("source", source.id, value)}
                  />
                ) : (
                  <label class="empty-state" xalign={0} label="No microphone source found." />
                )
              }
            </With>
          </box>

          <box class="section" orientation={Gtk.Orientation.VERTICAL}>
            {sectionTitle("Applications")}
            <With value={activeApp}>
              {(stream) =>
                stream ? (
                  <SliderRow
                    icon={stream.name?.toLowerCase() === "spotify" ? "󰓇" : "󰎆"}
                    label={
                      stream.title && stream.title !== stream.name
                        ? `${stream.name || "Unknown app"} - ${stream.title}`
                        : (stream.name || "Unknown app")
                    }
                    value={stream.percent}
                    muted={stream.muted}
                    onMute={() => toggleMute("stream", stream.id)}
                    onChange={(value) => setVolume("stream", stream.id, value)}
                  />
                ) : (
                  <label class="empty-state" xalign={0} label="No active playback streams." />
                )
              }
            </With>
          </box>

          <button class="full-mixer-button" onClicked={openFullMixer}>
            <label label="Open full mixer" />
          </button>
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
