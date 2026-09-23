#!/bin/bash
# Keep the Synaptics VFS5011-style fingerprint reader (06cb:00f0, HP OMEN)
# out of USB autosuspend: while suspended it never wakes for a press, so
# fingerprint auth at the lock screen, sudo, and polkit silently fail and
# the reader reads as dead after boot or resume.

if ! omarchy-hw-fingerprint; then
  exit 0
fi

# omarchy-hw-fingerprint already limits the 06cb vendor to userspace-driven
# readers, but autosuspend only breaks the VFS5011-family USB model. Restrict
# to the exact id this rule targets so unrelated Synaptics readers are left
# on the kernel's default policy.
found=false
for dev in /sys/bus/usb/devices/*; do
  [[ -r $dev/idVendor && -r $dev/idProduct ]] || continue
  [[ $(<"$dev/idVendor") == "06cb" && $(<"$dev/idProduct") == "00f0" ]] || continue
  found=true
  break
done
if ! $found; then
  exit 0
fi

sudo install -Dm644 "$OMARCHY_PATH/default/udev/fingerprint-autosuspend.rules" /etc/udev/rules.d/60-omarchy-fingerprint-autosuspend.rules
sudo udevadm control --reload-rules

# Apply to the live device: rules alone wait for the next attach, and the
# reader on a closed/open lid cycle would otherwise stay suspended.
for dev in /sys/bus/usb/devices/*; do
  [[ -r $dev/idVendor && -r $dev/idProduct ]] || continue
  [[ $(<"$dev/idVendor") == "06cb" && $(<"$dev/idProduct") == "00f0" ]] || continue
  sudo bash -c "echo on > '$dev/power/control'"
done