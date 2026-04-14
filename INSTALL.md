# NixOS HWC — Fresh Install Guide

This guide covers installing `hwc-laptop` from a NixOS minimal ISO onto the ThinkPad.
It assumes your Ventoy USB has the NixOS minimal ISO and `hwc-age-key.age` on it.

---

## 1. Boot

1. Plug in Ventoy USB
2. Power on, hold **F12** to open boot menu
3. Select the USB device
4. In Ventoy menu, select **nixos-minimal**

---

## 2. Network

**Ethernet:** Works automatically.

**WiFi:**
```bash
iwctl
device list                        # find interface name, e.g. wlan0
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "YourSSID"
exit
```

Test: `ping -c 1 nixos.org`

---

## 3. Partition the disk

> **Skip this section if reinstalling and keeping existing partitions.**
> Only repartition if you need a clean slate.

Identify your NVMe disk (should be `nvme0n1`, ~1TB):
```bash
lsblk
```

**All data will be lost.** Then:
```bash
gdisk /dev/nvme0n1
```

Inside gdisk:
```
o          # new GPT partition table
y          # confirm

n          # new partition
1          # partition number
           # accept default first sector
+512M      # size
ef00       # type: EFI system

n          # new partition
2          # partition number
           # accept default first sector
           # accept default last sector (rest of disk)
8300       # type: Linux filesystem

w          # write and exit
y          # confirm
```

---

## 4. Format

Use the exact UUIDs from `hardware.nix` so the config works without changes.
If the UUIDs change, the system won't boot until `hardware.nix` is updated.

```bash
# EFI boot partition
mkfs.fat -F 32 -i D278E61F /dev/nvme0n1p1

# Root partition
mkfs.ext4 -U 0ebc1df3-65ec-4125-9e73-2f88f7137dc7 /dev/nvme0n1p2
```

> If installing on different hardware, omit the `-i` and `-U` flags and let
> new UUIDs be generated. You'll need to update `machines/laptop/hardware.nix`
> after install — see the **New Hardware** section at the bottom.

---

## 5. Mount

```bash
mount /dev/nvme0n1p2 /mnt
mkdir -p /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot
```

---

## 6. Restore the age key

**This must be done before `nixos-install`.** Without it, agenix can't decrypt
secrets on first boot and all services that depend on secrets will fail.

Find and mount the Ventoy USB:
```bash
lsblk                              # find the Ventoy partition, usually sda1 or sdb1
mkdir -p /mnt/usb
mount /dev/sdb1 /mnt/usb           # adjust device if needed
```

Decrypt and install the key:
```bash
mkdir -p /mnt/etc/age
age -d /mnt/usb/hwc-age-key.age | tee /mnt/etc/age/keys.txt > /dev/null
chmod 600 /mnt/etc/age/keys.txt
umount /mnt/usb
```

The passphrase for `hwc-age-key.age` is in Bitwarden / Proton Pass.

---

## 7. Clone the repo

```bash
nix-shell -p git
git clone https://github.com/eriqueo/nixos-hwc /mnt/etc/nixos
```

---

## 8. Install

```bash
nixos-install --flake /mnt/etc/nixos#hwc-laptop --no-root-passwd
```

This takes a while on first install — it's building everything from the flake.
`--no-root-passwd` skips setting a root password since you use sudo via your user account.

---

## 9. Reboot

```bash
reboot
```

Remove the USB when the machine shuts down. systemd-boot will appear on next boot — select NixOS.

---

## 10. First boot checklist

Log in as `eric`, then run through these:

```bash
# Check secrets decrypted successfully
sudo ls /run/agenix/

# Check for failed services
systemctl --failed

# Reload shell to pick up aliases
reload

# Run home-manager standalone switch
hms
```

A few failed services on first boot is normal if any secrets didn't come through —
see the troubleshooting section below before panicking.

---

## Troubleshooting: secrets didn't decrypt

Symptoms: `/run/agenix/` is empty, services depending on passwords/tokens are failed.

**Check the key is present:**
```bash
sudo cat /etc/age/keys.txt         # should print an age private key
```

**If missing**, mount the Ventoy USB and restore it (same as step 6 but without `/mnt` prefix):
```bash
mkdir -p /tmp/usb
mount /dev/sdb1 /tmp/usb
sudo mkdir -p /etc/age
age -d /tmp/usb/hwc-age-key.age | sudo tee /etc/age/keys.txt > /dev/null
sudo chmod 600 /etc/age/keys.txt
umount /tmp/usb
```

Then trigger re-activation:
```bash
sudo nixos-rebuild switch --flake ~/.nixos#hwc-laptop
```

---

## New hardware (different machine)

If installing on hardware that isn't the ThinkPad, skip the UUID-preserving
format flags and do this after mounting at `/mnt`:

```bash
nixos-generate-config --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/machines/laptop/hardware.nix
rm /mnt/etc/nixos/configuration.nix    # don't need this, using flake
```

Review the generated `hardware.nix` and compare with the existing one before proceeding.
After first boot, commit the updated file to the repo.

---

## Reference

| | |
|---|---|
| Flake target | `#hwc-laptop` |
| Age key (on machine) | `/etc/age/keys.txt` |
| Age key (backup) | `hwc-age-key.age` on Ventoy USB |
| Config repo | `https://github.com/eriqueo/nixos-hwc` |
| Boot partition | `nvme0n1p1` · 512M · FAT32 · UUID `D278-E61F` |
| Root partition | `nvme0n1p2` · ~953G · ext4 · UUID `0ebc1df3-65ec-4125-9e73-2f88f7137dc7` |
| ThinkPad boot menu | Hold **F12** at power on |
