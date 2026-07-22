#!/bin/bash
set -euo pipefail

default_sink=$(pactl info | awk -F': ' '/Default Sink/ {print $2; exit}')
default_source=$(pactl info | awk -F': ' '/Default Source/ {print $2; exit}')

sinks_json=$(pactl --format=json list sinks)
sources_json=$(pactl --format=json list sources)
inputs_json=$(pactl --format=json list sink-inputs)

if [[ -z "${default_source}" || "${default_source}" == *.monitor ]]; then
  default_source=$(
    jq -r '[.[] | select(.name | endswith(".monitor") | not)][0].name // empty' <<<"$sources_json"
  )
fi

jq -n \
  --arg default_sink "$default_sink" \
  --arg default_source "$default_source" \
  --argjson sinks "$sinks_json" \
  --argjson sources "$sources_json" \
  --argjson inputs "$inputs_json" '
  def pct:
    (.volume["front-left"].value_percent // "0%")
    | sub("%$"; "")
    | tonumber;

  def stream_name:
    .properties["application.name"]
    // .properties["media.name"]
    // .properties["application.process.binary"]
    // "Unknown app";

  {
    sink: (
      [
        $sinks[]
        | select(.name == $default_sink)
        | {
            id: .name,
            description: .description,
            percent: pct,
            muted: .mute
          }
      ][0] // null
    ),
    source: (
      [
        $sources[]
        | select(.name == $default_source)
        | {
            id: .name,
            description: .description,
            percent: pct,
            muted: .mute
          }
      ][0] // null
    ),
    streams: [
      $inputs[]
      | {
          id: (.index | tostring),
          name: stream_name,
          title: (.properties["media.name"] // ""),
          percent: pct,
          muted: .mute
        }
    ]
  }'
