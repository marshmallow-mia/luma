# luma-fajita-platform

OnePlus 6T (fajita) platform services for the shared ARM image, installed as a
client-side layer (see devices/oneplus/fajita/INSTALL.md):

- remote processors: rmtfs and tqftpserv enabled (the modem and the Wi-Fi
  firmware need them);
- the A/B slot marked successful after a healthy boot (qbootctl -m after
  boot-complete.target);
- the wall clock kept across shutdown (the PM8998 RTC is not usable);
- a stable Bluetooth address derived from the SoC serial number;
- the OnePlus 6T ALSA UCM profile from sdm845-mainline/alsa-ucm-conf
  (commit 1b8d290e5aa2ca16b7f2fa8d74910ad19ef88b3a, BSD-3-Clause, see
  LICENSE.alsa-ucm-conf; trailing whitespace removed, otherwise unchanged) and a
  dist-alsa.conf without the snd-seq install rule;
- Android's hardware graphics path on the Adreno 630 when Android has no
  configuration yet;
- the handheld device class and the shared handheld dconf defaults
  (config/mobile/luma-shell-handheld.dconf);
- updates on request only (/etc/luma/update.conf).

Units are enabled by the package itself (wants links in /usr), including
rmtfs and tqftpserv, so a layered install needs no preset.
