#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Build the OnePlus 6T (fajita) kernel: the source lock in
# devices/oneplus/fajita/device.toml [kernel] (sdm845-mainline with
# postmarketOS's patches, prepared by scripts/kernel/prepare-source.py), the
# lock's base config with the [kernel] config merged over it
# (merge_config.sh -m), built with LLVM.
#
# OUTPUT_DIR receives:
#   Image.gz  the kernel for the boot image (scripts/mobile/build-fajita-boot-image.sh --kernel)
#   fajita.dtb the device tree appended to it (--dtb)
#   config    the merged configuration
#   modules/  stripped modules_install tree (--modules, and
#             scripts/packages/build-kernel-modules-luma-fajita.sh --tree)
#   cache/    downloaded source archives (hash-checked)
#   src/      the prepared source; obj/ the build tree (a second run is incremental)
#
# usage: build-fajita.sh OUTPUT_DIR
#
# Needs python3 >= 3.11, git, clang/lld/llvm, make, bc, flex, bison, perl,
# openssl and libelf headers, pahole. JOBS (default: nproc), KBUILD_BUILD_VERSION
# and KBUILD_BUILD_TIMESTAMP override the build defaults below.
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fail() { printf 'build-fajita: %s\n' "$*" >&2; exit 1; }
[ "$#" -eq 1 ] || { sed -n 's/^# usage: /usage: /p' "$0" >&2; exit 2; }
mkdir -p "$1"
out=$(realpath -e "$1")

eval "$(python3 - "$repo_root" <<'PY'
import json, shlex, sys, tomllib
root = sys.argv[1]
k = tomllib.load(open(root + "/devices/oneplus/fajita/device.toml", "rb"))["kernel"]
lock = json.load(open(root + "/" + k["source_lock"]))
assert lock["release"] == k["release"] and lock["device_tree"] == k["dtb"], "lock and device.toml disagree"
assert lock["base_config"]["source"] == "overlay"
v = {"lock": k["source_lock"], "release": k["release"], "fragment": k["config"], "dtb": k["dtb"],
     "base_member": lock["base_config"]["member"], "base_sha256": lock["base_config"]["sha256"]}
for key, val in v.items():
    print(f"{key}={shlex.quote(val)}")
PY
)"

if [ ! -f "$out/src/PREPARED.json" ]; then
  rm -rf "$out/src"
  python3 "$repo_root/scripts/kernel/prepare-source.py" --lock "$repo_root/$lock" \
    --cache "$out/cache" --output "$out/src" >/dev/null
fi
source_dir=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["linux"])' "$out/src/PREPARED.json")
overlay_dir=$(find "$out/src/overlay" -mindepth 1 -maxdepth 1 -type d)
base_config="$overlay_dir/$base_member"
echo "$base_sha256  $base_config" | sha256sum -c --quiet - || fail "$base_member differs from the lock"

obj="$out/obj"
mkdir -p "$obj"
cd "$source_dir"
K=(make O="$obj" ARCH=arm64 LLVM=1
   KBUILD_BUILD_USER=luma KBUILD_BUILD_HOST=kernel-fajita
   KBUILD_BUILD_VERSION="${KBUILD_BUILD_VERSION:-1}"
   KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-2026-11-12 00:00:00 UTC}")

scripts/kconfig/merge_config.sh -m -O "$obj" "$base_config" "$repo_root/$fragment" >/dev/null
"${K[@]}" -s olddefconfig
# Every assignment in the Luma config must survive olddefconfig.
grep -E '^(CONFIG_[A-Z0-9_]+=|# CONFIG_[A-Z0-9_]+ is not set)' "$repo_root/$fragment" | while IFS= read -r line; do
  grep -qxF -- "$line" "$obj/.config" || fail "$fragment: '$line' did not survive olddefconfig"
done
# The firmware set (devices/oneplus/fajita/firmware.manifest) is partly .zst.
grep -qx 'CONFIG_FW_LOADER_COMPRESS_ZSTD=y' "$obj/.config" || fail "the kernel cannot load .zst firmware"
[ "$("${K[@]}" -s kernelrelease)" = "$release" ] || fail "kernel release is $("${K[@]}" -s kernelrelease), not $release"

"${K[@]}" -j"${JOBS:-$(nproc)}" Image.gz modules "$dtb"
rm -rf "$out/modules"
"${K[@]}" INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH="$out/modules" modules_install >/dev/null
rm -f "$out/modules/lib/modules/$release/build" "$out/modules/lib/modules/$release/source"
install -m 0644 "$obj/arch/arm64/boot/Image.gz" "$out/Image.gz"
install -m 0644 "$obj/arch/arm64/boot/dts/$dtb" "$out/fajita.dtb"
install -m 0644 "$obj/.config" "$out/config"
{
  printf 'LOCK=%s\nRELEASE=%s\nDTB=%s\n' "$lock" "$release" "$dtb"
  printf 'IMAGE_SHA256=%s\n' "$(sha256sum "$out/Image.gz" | cut -d' ' -f1)"
  printf 'DTB_SHA256=%s\n' "$(sha256sum "$out/fajita.dtb" | cut -d' ' -f1)"
  printf 'CONFIG_SHA256=%s\n' "$(sha256sum "$out/config" | cut -d' ' -f1)"
  printf 'MODULE_COUNT=%s\n' "$(find "$out/modules/lib/modules/$release" -name '*.ko*' | wc -l)"
} >"$out/manifest.env"
cat "$out/manifest.env"
