#!/usr/bin/env bash
# Run inside the native Docker container. No sudo or emulation required.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# Preserve the historical Buildroot path even when invoked via /project.
if [[ -d /home/builduser/workspace/buildroot ]] &&
   [[ "$root/workspace/buildroot" -ef /home/builduser/workspace/buildroot ]]; then
    br=/home/builduser/workspace/buildroot
else
    br="$root/workspace/buildroot"
fi
action="${1:-build}"
case "$action" in
    prepare|build) ;;
    *) echo "Usage: $0 [prepare|build]" >&2; exit 2 ;;
esac
case "$(uname -m)" in
    x86_64)
        config="$root/configs/raspberrypizero_custom_defconfig"
        out="$br/output"
        expected=BR2_TOOLCHAIN_EXTERNAL_BOOTLIN_ARMV6_EABIHF_GLIBC_STABLE
        ;;
    aarch64|arm64)
        config="$root/configs/raspberrypizero_aarch64_host_defconfig"
        out="$root/workspace/output-aarch64"
        expected=BR2_TOOLCHAIN_BUILDROOT_GLIBC
        ;;
    *) echo "Unsupported build host: $(uname -m)" >&2; exit 2 ;;
esac
[[ -f "$br/Makefile" ]] || {
    echo "Initialize submodules: git submodule update --init --recursive" >&2
    exit 1
}
# Prevent mixing existing output from a different host architecture.
if [[ -f "$out/.pizero-build-host" ]] &&
   [[ "$(cat "$out/.pizero-build-host")" != "$(uname -m)" ]]; then
    echo "Output belongs to another host architecture: $out" >&2
    exit 1
fi
if [[ -f "$out/.config" ]]; then
    grep -qx "$expected=y" "$out/.config" &&
    grep -qx 'BR2_arm1176jzf_s=y' "$out/.config" || {
        echo "Existing configuration is incompatible: $out/.config" >&2
        echo "Back up and move this output directory before retrying; nothing was deleted." >&2
        exit 1
    }
else
    mkdir -p "$out"
    make -C "$br" O="$out" BR2_DEFCONFIG="$config" defconfig
fi
# Always check the resolved configuration, including after first initialization.
grep -qx "$expected=y" "$out/.config"
grep -qx 'BR2_arm1176jzf_s=y' "$out/.config"
uname -m > "$out/.pizero-build-host"
echo "Host: $(uname -m); output: $out"
if [[ "$action" == prepare ]]; then
    make -C "$br" O="$out" toolchain
else
    make -C "$br" O="$out"
fi
