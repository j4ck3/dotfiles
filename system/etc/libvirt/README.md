# Windows 11 VNC Console

The current `windows11` default is host-visible VNC with QXL video. It should not detach the AMD GPU or blank the host display.

Start it with:

```sh
windows11-console
```

That command starts `windows11` if needed and opens the normal virt-manager VNC console window.

## GPU Passthrough

The AMD GPU passthrough hook is opt-in. It only runs when this marker exists:

```sh
/etc/libvirt/hooks/windows11-gpu-passthrough.enabled
```

Do not create that marker for the normal VNC install workflow.
