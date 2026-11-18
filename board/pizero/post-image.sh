#!/bin/sh
# Run before Buildroot's Raspberry Pi post-image.sh (genimage).
set -eu
: "${BINARIES_DIR:?BINARIES_DIR is required}"
config="$BINARIES_DIR/rpi-firmware/config.txt"
[ -f "$config" ] || { echo "Missing boot config: $config" >&2; exit 1; }
# Append a global section so a preceding conditional section cannot hide I2C.
if ! grep -q '^# pizero2w-build: I2C$' "$config"; then
    printf '\n# pizero2w-build: I2C\n[all]\ndtparam=i2c_arm=on\n' >> "$config"
fi
