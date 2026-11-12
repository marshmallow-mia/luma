#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Build luma-fajita-platform (OnePlus 6T platform services) as a noarch RPM.
# Run it on Fedora (or in the Fedora 44 builder container) with rpm-build and
# systemd-rpm-macros installed.
#
#   build-luma-fajita-platform.sh [OUTPUT_DIR]

set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
for tool in gzip mktemp rpmbuild sha256sum tar; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'error: required OnePlus 6T platform build tool is missing: %s\n' "$tool" >&2
    exit 1
  }
done

output_dir=${1:-$repo_root/build/packages/luma-fajita-platform}
mkdir -p "$(dirname "$output_dir")"
work_dir=$(mktemp -d "$output_dir.work.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT INT TERM
# The RPM's directory modes come from this tree: drop a setgid bit and default
# ACLs inherited from the checkout (00755: GNU chmod keeps setgid under 0755).
chmod 00755 "$work_dir"
if command -v setfacl >/dev/null 2>&1; then setfacl -b -k "$work_dir" 2>/dev/null || true; fi
rpmbuild_dir="$work_dir/rpmbuild"
source_dir="$work_dir/luma-fajita-platform"
mkdir -p "$rpmbuild_dir"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} "$source_dir"
cp -R "$repo_root/src/luma-fajita-platform/." "$source_dir/"
# The shared handheld defaults, one source for every phone.
install -m 0644 "$repo_root/config/mobile/luma-shell-handheld.dconf" "$source_dir/luma-shell-handheld.dconf"
install -m 0644 "$repo_root/config/mobile/luma-greeter-handheld.dconf" "$source_dir/luma-greeter-handheld.dconf"
source_date_epoch=${SOURCE_DATE_EPOCH:-$(git -C "$repo_root" log -1 --format=%ct HEAD 2>/dev/null || date -u +%s)}
tar -C "$work_dir" --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 \
  --numeric-owner -cf - luma-fajita-platform | gzip -n >"$rpmbuild_dir/SOURCES/luma-fajita-platform.tar.gz"
install -m 0644 "$repo_root/LICENSE.md" "$rpmbuild_dir/SOURCES/LICENSE.md"
install -m 0644 "$repo_root/packaging/rpm/luma-fajita-platform.spec" "$rpmbuild_dir/SPECS/"
rpmbuild -ba --define "_topdir $rpmbuild_dir" "$rpmbuild_dir/SPECS/luma-fajita-platform.spec"

rm -rf "$output_dir"
install -d -m 0755 "$output_dir/RPMS/noarch" "$output_dir/SRPMS"
install -m 0644 "$rpmbuild_dir"/RPMS/noarch/*.rpm "$output_dir/RPMS/noarch/"
install -m 0644 "$rpmbuild_dir"/SRPMS/*.rpm "$output_dir/SRPMS/"
(
  cd "$output_dir"
  find RPMS SRPMS -type f -name '*.rpm' -exec sha256sum {} + | sort >SHA256SUMS
)
printf 'OnePlus 6T platform packages: %s\n' "$output_dir"
