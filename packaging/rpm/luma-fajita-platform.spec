# SPDX-License-Identifier: Apache-2.0
Name:           luma-fajita-platform
Version:        0.1.0
Release:        1.luma.1%{?dist}
Summary:        OnePlus 6T platform services for Luma
License:        Apache-2.0 AND BSD-3-Clause
URL:            https://github.com/SimplyLuma/luma
Source0:        luma-fajita-platform.tar.gz
Source1:        LICENSE.md

BuildArch:      noarch
BuildRequires:  systemd-rpm-macros
Requires:       bash
Requires:       bluez
Requires:       coreutils
Requires:       dconf
Requires:       grep
Requires:       qbootctl
Requires:       rmtfs
Requires:       systemd
Requires:       tqftpserv

%description
OnePlus 6T platform services on the shared Luma ARM image: rmtfs and
tqftpserv for the remote processors, A/B boot-slot success marking after a
healthy boot, the wall clock kept across shutdown, a stable Bluetooth address,
the OnePlus 6T sound card's UCM profile, Android's hardware graphics path, and
the handheld device class with the shared handheld defaults.

%prep
%autosetup -n luma-fajita-platform
cp %{SOURCE1} LICENSE.md

%build

%install
cp -a root/. %{buildroot}/
install -D -m 0644 luma-shell-handheld.dconf %{buildroot}%{_sysconfdir}/dconf/db/luma.d/10-luma-handheld
install -D -m 0644 luma-greeter-handheld.dconf %{buildroot}%{_sysconfdir}/dconf/db/gdm.d/10-luma-handheld
# Enabled by the package itself: a preset applies only on first install, and
# rmtfs and tqftpserv come from other packages.
install -d %{buildroot}%{_unitdir}/multi-user.target.wants %{buildroot}%{_unitdir}/sysinit.target.wants \
  %{buildroot}%{_unitdir}/timers.target.wants
for unit in luma-fajita-bluetooth-address luma-fajita-boot-success rmtfs tqftpserv; do
  ln -s ../$unit.service %{buildroot}%{_unitdir}/multi-user.target.wants/$unit.service
done
ln -s ../luma-clock-restore.service %{buildroot}%{_unitdir}/sysinit.target.wants/luma-clock-restore.service
ln -s ../luma-clock-save.timer %{buildroot}%{_unitdir}/timers.target.wants/luma-clock-save.timer

%check
grep -Fxq 'LUMA_DEVICE_CLASS=handheld' %{buildroot}%{_prefix}/lib/environment.d/90-luma-handheld.conf
grep -Fxq 'automatic_download = false' %{buildroot}%{_sysconfdir}/luma/update.conf
grep -Fxq 'ConditionFirmware=device-tree-compatible(oneplus,fajita)' %{buildroot}%{_unitdir}/luma-fajita-boot-success.service
grep -Fxq 'Requires=boot-complete.target' %{buildroot}%{_unitdir}/luma-fajita-boot-success.service
test ! -s %{buildroot}%{_unitdir}/boot.automount
# Comments only: no install rule.
! grep -qv '^#' %{buildroot}%{_sysconfdir}/modprobe.d/dist-alsa.conf
test -L "%{buildroot}%{_datadir}/alsa/ucm2/conf.d/sdm845/oneplus-OnePlus6T.conf"
grep -q 'File "/OnePlus/fajita/HiFi.conf"' "%{buildroot}%{_datadir}/alsa/ucm2/conf.d/sdm845/OnePlus 6T.conf"
bash -n %{buildroot}%{_libexecdir}/luma-fajita-bluetooth-address
for key in power-button-action sleep-inactive-ac-type sleep-inactive-battery-type color-scheme; do
  line=$(grep -x "$key='[a-z-]*'" %{buildroot}%{_sysconfdir}/dconf/db/luma.d/10-luma-handheld)
  grep -Fxq "$line" %{buildroot}%{_sysconfdir}/dconf/db/gdm.d/10-luma-handheld
done
test ! -e %{buildroot}%{_prefix}/lib/firmware

%posttrans
dconf update || :

%files
%license LICENSE.md LICENSE.alsa-ucm-conf
%doc README.md
%config(noreplace) %{_sysconfdir}/luma-device-class
%config(noreplace) %{_sysconfdir}/luma/update.conf
%config(noreplace) %{_sysconfdir}/modprobe.d/dist-alsa.conf
%config(noreplace) %{_sysconfdir}/dconf/db/luma.d/10-luma-handheld
%config(noreplace) %{_sysconfdir}/dconf/db/gdm.d/10-luma-handheld
%{_prefix}/lib/environment.d/90-luma-handheld.conf
%{_prefix}/lib/systemd/system-preset/60-luma-fajita-platform.preset
%{_prefix}/lib/tmpfiles.d/luma-fajita.conf
%{_unitdir}/boot.automount
%{_unitdir}/luma-clock-restore.service
%{_unitdir}/luma-clock-save.service
%{_unitdir}/luma-clock-save.timer
%{_unitdir}/luma-fajita-*.service
%{_unitdir}/multi-user.target.wants/*.service
%{_unitdir}/sysinit.target.wants/luma-clock-restore.service
%{_unitdir}/timers.target.wants/luma-clock-save.timer
%{_libexecdir}/luma-fajita-bluetooth-address
%{_datadir}/alsa/ucm2/OnePlus/fajita/
"%{_datadir}/alsa/ucm2/conf.d/sdm845/OnePlus 6T.conf"
%{_datadir}/alsa/ucm2/conf.d/sdm845/oneplus-OnePlus6T.conf

%changelog
* Thu Nov 12 2026 Project Luma <maintainers@projectluma.org> - 0.1.0-1.luma.1
- OnePlus 6T platform services for the shared ARM image: rmtfs and
  tqftpserv enabled, boot-slot success marking with qbootctl after
  boot-complete.target, the wall clock kept across shutdown, a Bluetooth
  address from the SoC serial number, the OnePlus 6T UCM profile, a
  dist-alsa.conf without the snd-seq install rule, Android's hardware
  graphics path, and the handheld device class and defaults.
