-- Keep the compositor environment minimal. Application-specific NVIDIA
-- variables belong in wrappers such as ~/.local/bin/helium-browser.
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("XCURSOR_SIZE", "32")
hl.env("__GL_VRR_ALLOWED", "0")
