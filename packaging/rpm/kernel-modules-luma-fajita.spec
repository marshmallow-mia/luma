# SPDX-License-Identifier: Apache-2.0
# Kernel modules of the OnePlus 6T kernel (source lock
# config/kernel/oneplus-fajita-7.1-rc1.json with config/kernel/oneplus-fajita.config,
# built by scripts/kernel/build-fajita.sh), the build whose Image.gz the
# OnePlus 6T boot image carries. Source0 is that build's
# /usr/lib/modules/<release> (scripts/packages/build-kernel-modules-luma-fajita.sh).
# The directory holds no vmlinuz, so rpm-ostree keeps the base image's kernel
# as the deployment's; the phone boots its own kernel from the boot partition
# and loads these. The package and the boot image change together.
%global kver 7.1.0-rc1-sdm845-luma
%global debug_package %{nil}
%global __strip /bin/true
%global _build_id_links none

Name:           kernel-modules-luma-fajita
Version:        7.1.0
Release:        0.rc1.1.luma.1%{?dist}
Summary:        Kernel modules for the OnePlus 6T kernel
License:        GPL-2.0-only
URL:            https://gitlab.com/sdm845-mainline/linux/-/tree/sdm845-7.1-rc1-r0
Source0:        fajita-kernel-modules.tar
ExclusiveArch:  aarch64
AutoReqProv:    no

%description
Loadable modules (and their modules.* indexes) for the OnePlus 6T kernel
%{kver}, which boots from the phone's boot partition.

%prep
%setup -q -c -T
tar -xf %{SOURCE0}
test -f usr/lib/modules/%{kver}/modules.dep

%build

%install
install -d %{buildroot}/usr/lib/modules
cp -a usr/lib/modules/%{kver} %{buildroot}/usr/lib/modules/

%check
m=%{buildroot}/usr/lib/modules/%{kver}
test ! -e $m/vmlinuz && test ! -e $m/initramfs.img && test ! -e $m/build && test ! -e $m/source
# Wi-Fi, the GPU/display driver and the remote processors.
for mod in ath10k_snoc msm qcom_q6v5_mss; do
  grep -Eq "/$mod\.ko(\.[a-z]+)?:" $m/modules.dep || grep -Eq "/$mod\.ko(\.[a-z]+)?$" $m/modules.builtin
done
test "$(find $m/kernel -name '*.ko*' | wc -l)" -gt 300

%files
%dir /usr/lib/modules/%{kver}
/usr/lib/modules/%{kver}/kernel/
/usr/lib/modules/%{kver}/modules.*

%changelog
* Thu Nov 12 2026 Project Luma <maintainers@projectluma.org> - 7.1.0-0.rc1.1.luma.1
- Modules of the OnePlus 6T kernel 7.1.0-rc1-sdm845-luma, for the shared ARM
  image.
