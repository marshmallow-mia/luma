#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Build kernel-modules-luma-fajita from the modules_install tree of
# scripts/kernel/build-fajita.sh (OUTPUT_DIR/modules). The package holds
# /usr/lib/modules/<release> without vmlinuz. Its kernel must be the one in
# the boot image. Nothing is compiled: run it on Fedora (or in the Fedora 44
# builder container) with rpm-build installed; any host architecture works.
#
#   build-kernel-modules-luma-fajita.sh MODULES_TREE [OUTPUT_DIR]

set -euo pipefail
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tree=$(realpath -e "${1:?usage: build-kernel-modules-luma-fajita.sh MODULES_TREE [OUTPUT_DIR]}")
output_dir=${2:-$repo_root/build/packages/kernel-modules-luma-fajita}
spec="$repo_root/packaging/rpm/kernel-modules-luma-fajita.spec"
kver=$(sed -n 's/^release = "\(.*\)"/\1/p' "$repo_root/devices/oneplus/fajita/device.toml" | head -n 1)
grep -q "^%global kver $kver\$" "$spec" ||
  { echo "error: the spec's kver is not device.toml's kernel release $kver" >&2; exit 1; }
[ -f "$tree/lib/modules/$kver/modules.dep" ] || { echo "error: $tree has no lib/modules/$kver" >&2; exit 1; }

mkdir -p "$(dirname "$output_dir")"
work_dir=$(mktemp -d "$output_dir.work.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT INT TERM
rpmbuild_dir="$work_dir/rpmbuild"
mkdir -p "$rpmbuild_dir"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} "$work_dir/tree/usr/lib/modules"
cp -a "$tree/lib/modules/$kver" "$work_dir/tree/usr/lib/modules/$kver"
rm -rf "$work_dir/tree/usr/lib/modules/$kver"/{build,source,vmlinuz,dtb}
tar -C "$work_dir/tree" --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -cf "$rpmbuild_dir/SOURCES/fajita-kernel-modules.tar" usr
install -m 0644 "$spec" "$rpmbuild_dir/SPECS/"
rpmbuild -ba --target aarch64 --define "_topdir $rpmbuild_dir" "$rpmbuild_dir/SPECS/kernel-modules-luma-fajita.spec"
rm -rf "$output_dir"
install -d -m 0755 "$output_dir/RPMS/aarch64" "$output_dir/SRPMS"
install -m 0644 "$rpmbuild_dir"/RPMS/aarch64/*.rpm "$output_dir/RPMS/aarch64/"
install -m 0644 "$rpmbuild_dir"/SRPMS/*.rpm "$output_dir/SRPMS/"
printf 'OnePlus 6T kernel modules package: %s\n' "$output_dir"
