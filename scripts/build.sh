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
        config_path="$br/.config"
        make_output_args=()
        expected=BR2_TOOLCHAIN_EXTERNAL_BOOTLIN_ARMV6_EABIHF_GLIBC_STABLE
        ;;
    aarch64|arm64)
        config="$root/configs/raspberrypizero_aarch64_host_defconfig"
        out="$root/workspace/output-aarch64"
        config_path="$out/.config"
        make_output_args=(O="$out")
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
check_config() {
    if ! grep -qx "$expected=y" "$config_path" ||
       ! grep -qx 'BR2_arm1176jzf_s=y' "$config_path"; then
        echo "Configuration validation failed: $config_path" >&2
        echo "Required: $expected=y and BR2_arm1176jzf_s=y" >&2
        grep -E '^BR2_(arm1176|TOOLCHAIN_BUILDROOT|TOOLCHAIN_EXTERNAL|PACKAGE_HOST_LINUX_HEADERS_CUSTOM)' "$config_path" >&2 || true
        echo "Back up the configuration before changing it; see README troubleshooting. No output was deleted." >&2
        return 1
    fi
}
if [[ -f "$config_path" ]]; then
    check_config
else
    mkdir -p "$out"
    make -C "$br" "${make_output_args[@]}" BR2_DEFCONFIG="$config" defconfig
fi
# Always check the resolved configuration, including after first initialization.
check_config
uname -m > "$out/.pizero-build-host"
echo "Host: $(uname -m); output: $out"
if [[ "$action" == prepare ]]; then
    make -C "$br" "${make_output_args[@]}" toolchain
else
    make -C "$br" "${make_output_args[@]}"
fi
