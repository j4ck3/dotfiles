#!/bin/bash
status=$(docker inspect --format='{{.State.Health.Status}}' gluetun-incognito 2>/dev/null)
case "$status" in
  healthy)   icon=$'\uf058' ; class="healthy" ;;
  unhealthy) icon=$'\uf057' ; class="unhealthy" ;;
  starting)  icon=$'\uf017' ; class="starting" ;;
  *)         icon=$'\uf2d8' ; class="unknown" ;;
esac
printf '{"text":"%s  gluetun","class":"%s","tooltip":"gluetun-incognito: %s"}\n' "$icon" "$class" "${status:-unknown}"
