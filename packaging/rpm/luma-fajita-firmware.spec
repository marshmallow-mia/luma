# SPDX-License-Identifier: Apache-2.0
# OnePlus 6T firmware for the shared ARM image: the 35 files and 8 links of
# devices/oneplus/fajita/firmware.manifest, as postmarketOS packages them
# (firmware-oneplus-sdm845 14-r0 from postmarketOS v26.06; linux-firmware-ath10k,
# -qca and -qcom 20260519-r0 from Alpine v3.24): the remote processors, GPU zap
# shader and Wi-Fi DSP under qcom/sdm845/OnePlus/enchilada (shared by the
# OnePlus 6 and 6T), the WCN3990 Wi-Fi and Bluetooth files, the Adreno 630 GMU
# and SQE microcode and the TFA98xx speaker amplifier profile. Source0 is that
# set as a tar of usr/lib/firmware (scripts/packages/assemble-luma-fajita-firmware.py).
# Installed in /usr/lib/firmware, not in /var. Files that the base image's
# linux-firmware packages also carry would conflict, so only the names that
# base image lacks are installed (checked against the commit when the package
# is built, scripts/packages/build-luma-fajita-firmware.sh --exclude).
Name:           luma-fajita-firmware
Version:        20260519
Release:        1.luma.1%{?dist}
Summary:        Firmware for the OnePlus 6T
License:        LicenseRef-Fedora-Firmware AND LicenseRef-OnePlus-Firmware
URL:            https://gitlab.com/sdm845-mainline/firmware-oneplus-sdm845
Source0:        fajita-firmware.tar
Source1:        firmware.manifest
Source2:        firmware.exclude
BuildArch:      noarch

%description
Firmware the OnePlus 6T kernel loads: modem, audio, compute and sensor DSPs,
video, GPU microcode and zap shader, Wi-Fi, Bluetooth and the speaker
amplifier profile.

%prep
%setup -q -c -T
tar -xf %{SOURCE0}
test -d usr/lib/firmware/qcom/sdm845/OnePlus/enchilada

%build

%install
install -d %{buildroot}/usr/lib/firmware
cp -a usr/lib/firmware/. %{buildroot}/usr/lib/firmware/
# Paths the base image already ships (one per line, relative to /usr/lib/firmware).
while IFS= read -r relative; do
  [ -n "$relative" ] || continue
  rm -f "%{buildroot}/usr/lib/firmware/$relative"
done < %{SOURCE2}
find %{buildroot}/usr/lib/firmware -depth -type d -empty -delete
find %{buildroot}/usr/lib/firmware -type f -o -type l | sed "s|^%{buildroot}||" | sort > files.list

%check
# Every manifest file the package installs, at its path, with its digest.
fw=%{buildroot}/usr/lib/firmware
files=0
while IFS="$(printf '\t')" read -r kind mode digest relative target; do
  case "$kind" in
    F) [ -e "$fw/$relative" ] || continue
       echo "$digest  $fw/$relative" | sha256sum -c --quiet -
       files=$((files + 1)) ;;
    L) [ -L "$fw/$relative" ] || continue
       test "$(readlink "$fw/$relative")" = "$target" ;;
  esac
done < %{SOURCE1}
test "$files" -gt 20
test -f $fw/qcom/sdm845/OnePlus/enchilada/a630_zap.mbn
test -f $fw/qcom/sdm845/OnePlus/enchilada/modem.mbn

%files -f files.list

%changelog
* Thu Nov 12 2026 Project Luma <maintainers@projectluma.org> - 20260519-1.luma.1
- The OnePlus 6T firmware set (devices/oneplus/fajita/firmware.manifest) as a
  package in /usr/lib/firmware.
