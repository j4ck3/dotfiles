#version 320 es
// Passthrough — used when brightness=100% and night light off.
// Do not set decoration:screen_shader to "" (Hyprland treats that as empty source).
precision mediump float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;

void main() {
    fragColor = texture(tex, v_texcoord);
}
