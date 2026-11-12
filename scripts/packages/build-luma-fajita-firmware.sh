#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Build luma-fajita-firmware from the OnePlus 6T firmware tar
# (scripts/packages/assemble-luma-fajita-firmware.py). With --ostree-repo and
# --ref, the manifest paths that commit's /usr/lib/firmware already has are left
# out, so the package installs over it without file conflicts. Run it on
# Fedora (or in the Fedora 44 builder container) with rpm-build and ostree.
#
#   build-luma-fajita-firmware.sh FIRMWARE_TAR [--ostree-repo REPO --ref REF] [--output DIR]

set -euo pipefail
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
usage='usage: build-luma-fajita-firmware.sh FIRMWARE_TAR [--ostree-repo REPO --ref REF] [--output DIR]'
tar_file=$(realpath -e "${1:?$usage}"); shift
ostree_repo="" ref="" output_dir="$repo_root/build/packages/luma-fajita-firmware"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ostree-repo) ostree_repo=$(realpath -e "${2:?}"); shift 2 ;;
    --ref) ref=${2:?}; shift 2 ;;
    --output) output_dir=${2:?}; shift 2 ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
done
manifest=$repo_root/devices/oneplus/fajita/firmware.manifest
expected=$(sed -n 's/^manifest_sha256 = "\(.*\)"/\1/p' "$repo_root/devices/oneplus/fajita/device.toml")
echo "$expected  $manifest" | sha256sum -c --quiet - || { echo "error: firmware.manifest does not match device.toml" >&2; exit 1; }
entries=$(grep -cE '^(F|L)	' "$manifest")
[ "$(tar -tf "$tar_file" | grep -vc '/$')" = "$entries" ] || { echo "error: the tar is not the manifest's set" >&2; exit 1; }

mkdir -p "$(dirname "$output_dir")"
work_dir=$(mktemp -d "$output_dir.work.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT INT TERM
rpmbuild_dir="$work_dir/rpmbuild"
mkdir -p "$rpmbuild_dir"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
: >"$rpmbuild_dir/SOURCES/firmware.exclude"
if [ -n "$ostree_repo" ]; then
  [ -n "$ref" ] || { echo "$usage" >&2; exit 2; }
  while IFS="$(printf '\t')" read -r kind _mode _digest relative _target; do
    case "$kind" in F|L) ;; *) continue ;; esac
    if ostree --repo="$ostree_repo" ls "$ref" "/usr/lib/firmware/$relative" >/dev/null 2>&1; then
      printf '%s\n' "$relative" >>"$rpmbuild_dir/SOURCES/firmware.exclude"
    fi
  done <"$manifest"
  printf 'left out (in %s): %s\n' "$ref" "$(wc -l <"$rpmbuild_dir/SOURCES/firmware.exclude")"
fi
install -m 0644 "$tar_file" "$rpmbuild_dir/SOURCES/fajita-firmware.tar"
install -m 0644 "$manifest" "$rpmbuild_dir/SOURCES/firmware.manifest"
install -m 0644 "$repo_root/packaging/rpm/luma-fajita-firmware.spec" "$rpmbuild_dir/SPECS/"
rpmbuild -ba --define "_topdir $rpmbuild_dir" "$rpmbuild_dir/SPECS/luma-fajita-firmware.spec"
rm -rf "$output_dir"
install -d -m 0755 "$output_dir/RPMS/noarch" "$output_dir/SRPMS"
install -m 0644 "$rpmbuild_dir"/RPMS/noarch/*.rpm "$output_dir/RPMS/noarch/"
install -m 0644 "$rpmbuild_dir"/SRPMS/*.rpm "$output_dir/SRPMS/"
install -m 0644 "$rpmbuild_dir/SOURCES/firmware.exclude" "$output_dir/firmware.exclude"
printf 'OnePlus 6T firmware package: %s\n' "$output_dir"
