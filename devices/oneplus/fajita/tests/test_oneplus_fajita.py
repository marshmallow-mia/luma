# SPDX-License-Identifier: Apache-2.0
import hashlib
import json
from pathlib import Path
import re
import tomllib
import unittest

DEVICE = Path(__file__).resolve().parents[1]
ROOT = DEVICE.parents[2]


def load(path: Path) -> dict:
    return tomllib.loads(path.read_text())


class OnePlusFajitaProfile(unittest.TestCase):
    def setUp(self):
        self.device = load(DEVICE / 'device.toml')
        self.boot = load(DEVICE / 'boot.toml')
        self.soc = load(ROOT / 'socs' / 'qcom' / 'sdm845' / 'soc.toml')

    def test_experimental_on_sdm845_with_header_v0(self):
        self.assertEqual(self.device['tier'], 'experimental')
        self.assertEqual(self.device['soc'], 'qcom/sdm845')
        self.assertEqual(self.soc['boot']['format'], 'android-boot-v0')
        self.assertNotIn('format', self.boot)
        self.assertEqual(self.boot['partition_size'], 64 * 1024 * 1024)

    def test_no_published_release_or_own_ref_is_invented(self):
        self.assertNotIn('tag', self.device['kernel'])
        self.assertNotIn('releases', self.device)
        # The phone follows the shared ARM nightly ref.
        self.assertNotIn('updates', self.device)

    def test_kernel_lock_matches_manifest(self):
        lock = json.loads((ROOT / self.device['kernel']['source_lock']).read_text())
        self.assertEqual(lock['release'], self.device['kernel']['release'])
        self.assertEqual(lock['device_tree'], self.device['kernel']['dtb'])
        self.assertEqual(set(lock['sources']), {'linux', 'overlay'})

    def test_firmware_manifest_is_exact(self):
        manifest = (DEVICE / 'firmware.manifest').read_bytes()
        self.assertEqual(hashlib.sha256(manifest).hexdigest(),
                         self.device['firmware']['manifest_sha256'])
        self.assertIn(b'qcom/sdm845/OnePlus/enchilada/modem.mbn', manifest)
        self.assertIn(b'ath10k/WCN3990/hw1.0/wlanmdsp.mbn.zst', manifest)

    def test_guide_writes_only_boot_and_userdata(self):
        guide = (DEVICE / 'INSTALL.md').read_text()
        written = set(re.findall(r'fastboot\s+(?:flash|erase|format)(?::\S+)?\s+(\S+)', guide))
        self.assertEqual(written, {'userdata', 'boot_a', 'boot_b'})
        for partition in ('vbmeta', 'dtbo', 'modem_', 'modemst', 'persist', 'fsg', 'fsc'):
            self.assertNotRegex(guide, rf'fastboot\s+(?:flash|erase|format)\S*\s+{partition}')

    def test_initramfs_base_is_pinned(self):
        initramfs = self.device['initramfs']
        self.assertEqual(initramfs['base'], 'postmarketos-initramfs 3.11.0-r1')
        self.assertTrue(initramfs['base_boot_image'].startswith('https://images.postmarketos.org/'))
        self.assertRegex(initramfs['base_boot_image_sha256'], r'^[0-9a-f]{64}$')
        script = ROOT / initramfs['init_functions']
        self.assertEqual(hashlib.sha256(script.read_bytes()).hexdigest(), initramfs['init_functions_sha256'])

    def test_init_functions_boot_luma_ostree(self):
        text = (ROOT / self.device['initramfs']['init_functions']).read_text()
        # Everything Luma does is gated on the boot image's marker.
        self.assertIn('[ -e /etc/luma-ostree-boot ] || return 0', text)
        self.assertIn('/usr/lib/ostree/ostree-prepare-root /sysroot "$cmdline"', text)
        self.assertEqual(text.count('if ! luma_prepare_ostree_root; then'), 2)
        # /boot stays on the root filesystem, where ostree writes its entries.
        self.assertIn('[ "$1" = /sysroot/boot ] && [ -e /etc/luma-ostree-boot ]', text)
        # The /var stores serve only until the deployment has its own files.
        self.assertIn('/var/lib/luma/device-firmware', text)
        self.assertIn('/var/lib/luma/device-modules', text)
        marker = re.search(r'^luma_fajita_firmware_marker=(\S+)$', text, re.M).group(1)
        self.assertIn(b'\t' + marker.encode() + b'\t', (DEVICE / 'firmware.manifest').read_bytes())

    def test_shared_hook_accepts_the_marker(self):
        hook = ROOT / 'scripts/mobile/common/initramfs/hooks-extra/50-luma-ostree-default.sh'
        self.assertIn('[ -e /etc/luma-ostree-boot ] || [ -e /etc/luma-fp6-ostree ] || exit 0', hook.read_text())

    def test_packages_follow_the_profile(self):
        spec = (ROOT / 'packaging/rpm/kernel-modules-luma-fajita.spec').read_text()
        self.assertIn(f"%global kver {self.device['kernel']['release']}\n", spec)
        self.assertEqual(self.device['firmware']['store'], '/usr/lib/firmware')
        platform = ROOT / 'src/luma-fajita-platform/root/usr/lib/systemd/system/luma-fajita-boot-success.service'
        self.assertIn('ConditionFirmware=device-tree-compatible(oneplus,fajita)', platform.read_text())

    def test_boot_image_keeps_the_userdata_uuids(self):
        script = (ROOT / 'scripts/mobile/build-fajita-boot-image.sh').read_text()
        userdata = (ROOT / 'scripts/mobile/build-phone-userdata.sh').read_text()
        for name in ('root_uuid', 'boot_uuid'):
            value = re.search(rf'^{name}=(\S+)$', userdata, re.M).group(1)
            self.assertIn(f'{name}={value}\n', script)
        self.assertIn('--header_version 0', script)


if __name__ == '__main__':
    unittest.main()
