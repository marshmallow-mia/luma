#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# OnePlus 6T (fajita) boot image for the shared ARM image: Android boot image
# header v0 (socs/qcom/sdm845/soc.toml), Image.gz with the fajita DTB appended,
# and a ramdisk of two concatenated cpio archives (the kernel unpacks them in
# order; later files replace earlier ones):
#
#   1. the ramdisk of the postmarketOS boot image named in
#      devices/oneplus/fajita/device.toml [initramfs] base_boot_image
#      (postmarketos-initramfs 3.11.0-r1), unmodified;
#   2. a Luma archive: scripts/mobile/fajita-init-functions.sh as
#      /init_functions.sh, this kernel's builds of the base ramdisk's modules,
#      the shared OSTree boot resolver (scripts/mobile/common/initramfs),
#      ostree-prepare-root, its configuration and its Fedora libraries from the
#      OSTree commit the phone deploys, /etc/luma-ostree-boot and the clock
#      floor /etc/luma-clock-floor.
#
# The command line is boot.toml's, then the generic phone userdata image's
# filesystems (pmos_root_uuid, pmos_boot_uuid). It names the slot link
# (ostree=/ostree/root.a); the bootloader appends androidboot.slot_suffix. One
# boot image serves every nightly, rpm-ostree upgrade and rollback; it changes
# only with the kernel or the initramfs. No AVB footer: vbmeta stays as OnePlus
# ships it and the bootloader is unlocked (boot.toml [avb]).
#
# usage: build-fajita-boot-image.sh --base-boot FILE --kernel-dir DIR
#          --ostree-repo REPO --ref REF --output FILE
#   --base-boot   the downloaded base_boot_image (.img.xz, as published)
#   --kernel-dir  OUTPUT_DIR of scripts/kernel/build-fajita.sh (Image.gz,
#                 fajita.dtb, config, modules/)
#   --ref         the commit (or ref) whose ostree-prepare-root boots it
#
# Needs mkbootimg and unpack_bootimg (Fedora android-tools; MKBOOTIMG,
# UNPACK_BOOTIMG override), ostree, cpio, gzip, xz, zstd, depmod, llvm-readelf or
# readelf, and python3 >= 3.11. SOURCE_DATE_EPOCH sets the clock floor and
# archive times (default: the commit's date).
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
device="$repo_root/devices/oneplus/fajita"
shared="$repo_root/scripts/mobile/common/initramfs"
fail() { printf 'build-fajita-boot-image: %s\n' "$*" >&2; exit 1; }
# The generic phone userdata image's filesystems (scripts/mobile/build-phone-userdata.sh).
root_uuid=03797c05-cf87-4eda-adc4-6ce111baf2d3
boot_uuid=032D-57AD

base="" kdir="" ostree_repo="" ref="" output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base-boot) base=$(realpath -e "${2:?}"); shift 2 ;;
    --kernel-dir) kdir=$(realpath -e "${2:?}"); shift 2 ;;
    --ostree-repo) ostree_repo=$(realpath -e "${2:?}"); shift 2 ;;
    --ref) ref=${2:?}; shift 2 ;;
    --output) output=${2:?}; shift 2 ;;
    *) sed -n 's/^# usage: /usage: /p' "$0" >&2; exit 2 ;;
  esac
done
[ -n "$base" ] && [ -n "$kdir" ] && [ -n "$ostree_repo" ] && [ -n "$ref" ] && [ -n "$output" ] ||
  fail "missing arguments"
for f in "$shared/luma-ostree-boot.sh" "$shared/hooks-extra/50-luma-ostree-default.sh" \
         "$kdir/Image.gz" "$kdir/fajita.dtb" "$kdir/config"; do
  [ -f "$f" ] || fail "missing $f"
done
mkbootimg=${MKBOOTIMG:-mkbootimg} unpack=${UNPACK_BOOTIMG:-unpack_bootimg}
readelf=$(command -v llvm-readelf || command -v readelf) || fail "no readelf"

eval "$(python3 - "$device" "$repo_root/socs/qcom/sdm845/soc.toml" <<'PY'
import shlex, sys, tomllib
d = sys.argv[1]
dev = tomllib.load(open(d + "/device.toml", "rb"))
boot = tomllib.load(open(d + "/boot.toml", "rb"))
soc = tomllib.load(open(sys.argv[2], "rb"))["boot"]
assert soc["format"] == "android-boot-v0" and soc["dtb_in_boot_image"]
o = soc["offsets"]
v = {
    "base_sha256": dev["initramfs"]["base_boot_image_sha256"],
    "base_url": dev["initramfs"]["base_boot_image"],
    "ramdisk_sha256": dev["initramfs"]["ramdisk_sha256"],
    "init_functions": dev["initramfs"]["init_functions"],
    "init_functions_sha256": dev["initramfs"]["init_functions_sha256"],
    "release": dev["kernel"]["release"],
    "cmdline_fixed": " ".join(boot["cmdline"]["args"]),
    "forbidden": " ".join(boot["cmdline"]["forbidden"]),
    "partition_size": boot["partition_size"],
    "page_size": soc["page_size"],
    "off_base": hex(o["base"]), "off_kernel": hex(o["kernel"]), "off_ramdisk": hex(o["ramdisk"]),
    "off_second": hex(o["second"]), "off_tags": hex(o["tags"]),
}
assert boot["avb"]["footer"] == "none"
for k, val in v.items():
    print(f"{k}={shlex.quote(str(val))}")
PY
)"

echo "$base_sha256  $base" | sha256sum -c --quiet - || fail "$base is not $base_url (device.toml)"
script="$repo_root/$init_functions"
echo "$init_functions_sha256  $script" | sha256sum -c --quiet - || fail "$init_functions differs from device.toml"
for opt in CONFIG_RD_GZIP=y CONFIG_RD_ZSTD=y CONFIG_BLK_DEV_INITRD=y; do
  grep -qx "$opt" "$kdir/config" || fail "the kernel lacks $opt"
done
commit=$(ostree --repo="$ostree_repo" rev-parse "$ref")
# The commit's date ("Date:  2026-11-11 06:35:44 +0000").
epoch=${SOURCE_DATE_EPOCH:-$(date -u -d "$(ostree --repo="$ostree_repo" show "$commit" | sed -n 's/^Date: *//p' | head -n 1)" +%s)}
case "$epoch" in ''|*[!0-9]*) fail "cannot read the commit's date" ;; esac

work=$(mktemp -d "${TMPDIR:-/var/tmp}/fajita-boot.XXXXXX")
trap 'rm -rf "$work"' EXIT
umask 022
xz -dc "$base" >"$work/base.img"
"$unpack" --boot_img "$work/base.img" --out "$work/in" >/dev/null
echo "$ramdisk_sha256  $work/in/ramdisk" | sha256sum -c --quiet - || fail "the base ramdisk differs from device.toml"
mkdir "$work/base"
zstd -dcq "$work/in/ramdisk" | (cd "$work/base" && cpio --quiet -i --no-absolute-filenames --nonmatching 'dev/*' 2>/dev/null) ||
  fail "cannot read the base ramdisk"
grep -q '^INITRAMFS_PKG_VERSION="3.11.0-r1"$' "$work/base/init" || fail "the base ramdisk is not postmarketos-initramfs 3.11.0-r1"

o="$work/overlay"
mkdir -p "$o/etc" "$o/usr/lib/luma" "$o/hooks-extra" "$o/usr/lib/ostree" "$o/usr/lib64"
install -m 0644 "$script" "$o/init_functions.sh"
install -m 0644 "$shared/luma-ostree-boot.sh" "$o/usr/lib/luma/ostree-boot.sh"
install -m 0755 "$shared/hooks-extra/50-luma-ostree-default.sh" "$o/hooks-extra/50-luma-ostree-default.sh"
: >"$o/etc/luma-ostree-boot"
printf '%s\n' "$epoch" >"$o/etc/luma-clock-floor"

# This kernel's builds of the base ramdisk's modules, their dependencies and
# indexes. /lib is /usr/lib in the base ramdisk.
mods="$kdir/modules/lib/modules/$release"
[ -f "$mods/modules.dep" ] || fail "$kdir/modules has no lib/modules/$release"
python3 - "$work/base/usr/lib/modules" "$mods" "$o/usr/lib/modules/$release" <<'PY'
import os, re, shutil, sys
from pathlib import Path
base, mods, dest = (Path(p) for p in sys.argv[1:])
name = lambda p: re.sub(r"\.ko(\.(gz|xz|zst))?$", "", Path(p).name).replace("-", "_")
wanted = {name(p) for p in base.glob("*/kernel/**/*.ko*")}
deps = {}
for line in (mods / "modules.dep").read_text().splitlines():
    mod, _, rest = line.partition(":")
    deps[mod] = rest.split()
by_name = {name(m): m for m in deps}
missing = sorted(w for w in wanted if w not in by_name)
builtin = {name(l) for l in (mods / "modules.builtin").read_text().split()}
if [m for m in missing if m not in builtin]:
    sys.exit(f"modules missing from this kernel: {[m for m in missing if m not in builtin]}")
todo, seen = [by_name[w] for w in wanted if w in by_name], set()
while todo:
    m = todo.pop()
    if m in seen:
        continue
    seen.add(m)
    todo += deps[m]
for m in sorted(seen):
    (dest / m).parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(mods / m, dest / m)
for f in ("modules.builtin", "modules.builtin.modinfo", "modules.order"):
    shutil.copy2(mods / f, dest / f)
print(f"{len(seen)} initramfs modules")
PY
depmod -b "$o/usr" "$release"
# initramfs.load lists module names, not paths: the base file stays valid.

# ostree-prepare-root with its configuration and libraries, from the commit.
ostree --repo="$ostree_repo" cat "$commit" /usr/lib/ostree/ostree-prepare-root >"$o/usr/lib/ostree/ostree-prepare-root"
chmod 0755 "$o/usr/lib/ostree/ostree-prepare-root"
if ostree --repo="$ostree_repo" cat "$commit" /usr/lib/ostree/prepare-root.conf >"$work/prepare-root.conf" 2>/dev/null; then
  install -m 0644 "$work/prepare-root.conf" "$o/usr/lib/ostree/prepare-root.conf"
fi
python3 - "$ostree_repo" "$commit" "$o" "$readelf" <<'PY'
import posixpath, subprocess, sys
from pathlib import Path
repo, commit, root, readelf = sys.argv[1], sys.argv[2], Path(sys.argv[3]), sys.argv[4]
def ostree(*a):
    return subprocess.run(["ostree", f"--repo={repo}", *a], check=True, capture_output=True).stdout
def resolve(path):
    # Follow symlinks inside the commit (/lib is /usr/lib there too).
    for _ in range(16):
        if path.startswith("/lib/") or path.startswith("/lib64/"):
            path = "/usr" + path
        out = ostree("ls", commit, path).decode().split()
        if not out[0].startswith("l"):
            return path
        target = out[-1]
        path = posixpath.normpath(target if target.startswith("/") else posixpath.join(posixpath.dirname(path), target))
    raise SystemExit(f"symlink loop at {path}")
def needed(f):
    out = subprocess.run([readelf, "-d", "-l", str(f)], check=True, capture_output=True, text=True).stdout
    libs = [l.split("[")[1].split("]")[0] for l in out.splitlines() if "(NEEDED)" in l]
    interp = [l.split(":", 1)[1].strip(" ]") for l in out.splitlines() if "Requesting program interpreter" in l]
    return libs, interp
todo, done = [root / "usr/lib/ostree/ostree-prepare-root"], set()
while todo:
    libs, interp = needed(todo.pop())
    for i in interp:
        if i not in done:
            done.add(i)
            data = ostree("cat", commit, resolve(i))
            dest = root / i.lstrip("/").replace("lib/", "usr/lib/", 1) if i.startswith("/lib/") else root / i.lstrip("/")
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data); dest.chmod(0o755)
    for lib in libs:
        if lib in done:
            continue
        done.add(lib)
        # Fedora's default library directories (ld.so searches both).
        for directory in ("/usr/lib64", "/usr/lib"):
            try:
                path = resolve(f"{directory}/{lib}")
            except subprocess.CalledProcessError:
                continue
            break
        else:
            raise SystemExit(f"{lib} is not in the commit")
        dest = root / directory.lstrip("/") / lib
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(ostree("cat", commit, path)); dest.chmod(0o755)
        todo.append(dest)
print(f"{len(done)} files for ostree-prepare-root")
PY

# 00755: GNU chmod keeps a directory's setgid bit (inherited from TMPDIR) under 0755.
find "$o" -type d -exec chmod 00755 {} +
find "$o" -exec touch -h -d "@$epoch" {} +
(cd "$o" && find . -mindepth 1 | LC_ALL=C sort | cpio --quiet --reproducible -o -H newc -R 0:0) | gzip -9n >"$work/overlay.cpio.gz"
cat "$work/in/ramdisk" "$work/overlay.cpio.gz" >"$work/ramdisk"
cat "$kdir/Image.gz" "$kdir/fajita.dtb" >"$work/kernel"

cmdline="$cmdline_fixed pmos_root_uuid=$root_uuid pmos_boot_uuid=$boot_uuid"
for word in $forbidden androidboot.slot_suffix; do
  case " $cmdline " in *" $word"*) fail "forbidden argument $word in: $cmdline" ;; esac
done
case " $cmdline " in *" ostree=/ostree/root.a "*) ;; *) fail "the command line must name ostree=/ostree/root.a" ;; esac

"$mkbootimg" --header_version 0 --pagesize "$page_size" --base "$off_base" \
  --kernel_offset "$off_kernel" --ramdisk_offset "$off_ramdisk" --second_offset "$off_second" \
  --tags_offset "$off_tags" --kernel "$work/kernel" --ramdisk "$work/ramdisk" \
  --cmdline "$cmdline" --output "$work/boot.img"

# Check the result the way the bootloader and the initramfs will see it.
"$unpack" --boot_img "$work/boot.img" --out "$work/check" --format mkbootimg >"$work/check.args"
grep -Fq -- "--header_version 0" "$work/check.args" || fail "not a header v0 image"
grep -Fq -- "--pagesize 0x00001000" "$work/check.args" || grep -Fq -- "--pagesize 4096" "$work/check.args" || fail "page size"
grep -Fq -- "--cmdline '$cmdline'" "$work/check.args" || fail "command line not in the image"
cmp -s "$work/check/kernel" "$work/kernel" && cmp -s "$work/check/ramdisk" "$work/ramdisk" || fail "kernel or ramdisk changed"
python3 - "$work/overlay.cpio.gz" "$script" "$release" <<'PY' || fail "the ramdisk lacks the OSTree boot pieces"
import gzip, sys
data, files, i = gzip.open(sys.argv[1]).read(), {}, 0
while i < len(data):
    if data[i:i + 6] != b"070701":
        i += 1
        continue
    h = [int(data[i + 6 + 8 * n:i + 14 + 8 * n], 16) for n in range(13)]
    mode, size, namesize = h[1], h[6], h[11]
    name = data[i + 110:i + 110 + namesize - 1].decode()
    start = (i + 110 + namesize + 3) & ~3
    files[name.lstrip("./")] = (mode, data[start:start + size])
    i = (start + size + 3) & ~3
assert files["init_functions.sh"][1] == open(sys.argv[2], "rb").read(), "init_functions.sh"
for name in ("etc/luma-ostree-boot", "etc/luma-clock-floor", "usr/lib/luma/ostree-boot.sh",
             f"usr/lib/modules/{sys.argv[3]}/modules.dep", "usr/lib/ld-linux-aarch64.so.1"):
    assert name in files, name
for name in ("hooks-extra/50-luma-ostree-default.sh", "usr/lib/ostree/ostree-prepare-root"):
    assert files[name][0] & 0o111, name
PY
size=$(stat -c %s "$work/boot.img")
[ "$size" -le "$partition_size" ] || fail "the image ($size bytes) does not fit the boot partition ($partition_size)"

install -D -m 0644 "$work/boot.img" "$output"
printf 'CMDLINE=%s\nCOMMIT=%s\nCLOCK_FLOOR=%s\nBOOT_SHA256=%s\nBASE_BOOT_SHA256=%s\nRAMDISK_OVERLAY_SHA256=%s\n' \
  "$cmdline" "$commit" "$epoch" \
  "$(sha256sum "$output" | cut -d' ' -f1)" "$base_sha256" "$(sha256sum "$work/overlay.cpio.gz" | cut -d' ' -f1)"
