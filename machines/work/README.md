# hwc-work: install the MS-02 and make the first flake switch

`#hwc-work` is the staged work-server output in the fleet flake. It provides the
existing headless CLI/Home Manager setup, SSH, Tailscale, Podman and server tools.
It leaves CouchDB, Nightly Builds, Refinery, business services, public routes and
storage mounts on `hwc-server`. No production data is copied by activating it.

## At the desk: install a reachable base system

Use an external monitor and keyboard on the MS-02. The laptop and MS-02 each
connect to the same Wi-Fi; the laptop's connection does not automatically share
internet with the MS-02. The stock minimal installer may need to download
packages, and the fleet flake has private inputs. Have the Wi-Fi password or
phone USB tethering available. Keep `hwc-server` running throughout this stage.
This first install uses only the small configuration below. It does not import
the fleet flake or agenix, so neither an age key nor a decrypted secret is
needed to log in. Do not use `nixos-install --flake` at this stage.

1. On the laptop, write the
   [NixOS 25.11 minimal x86_64 ISO](https://channels.nixos.org/nixos-25.11/latest-nixos-minimal-x86_64-linux.iso)
   to a USB stick.
   Boot the MS-02 from that stick in UEFI mode. If the installer will not boot,
   check whether Secure Boot is enabled; the standard installer is unsigned.
   At the installer prompt, become root with `sudo -i` and confirm UEFI:

   ```sh
   test -d /sys/firmware/efi/efivars && echo UEFI
   ```

2. Connect the **installer** to Wi-Fi. On the minimal ISO, `wpa_supplicant`
   manages Wi-Fi. `wpa_passphrase` asks for the password without putting it in
   shell history; its temporary config stays on the live USB system. Replace
   the SSID, then check that downloads and DNS work:

   ```sh
   ip -br link
   umask 077
   wpa_passphrase 'YOUR_WIFI_SSID' > /etc/wpa_supplicant.conf
   systemctl restart wpa_supplicant
   ping -c 2 cache.nixos.org
   ```

   If Wi-Fi is not detected or the ping fails, use phone USB tethering and
   repeat the ping. Do not count on a stock ISO completing this setup fully
   offline.

3. Identify the **internal 1 TB SSD by model and serial**. The next commands
   erase the selected disk, including any preinstalled Windows installation.
   Set `TARGET_DISK` to its whole-disk `/dev/disk/by-id/nvme-...` path, not a
   partition or the installer USB. Stop if its size and model do not match:

   ```sh
   lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,TYPE
   export TARGET_DISK=/dev/disk/by-id/nvme-REPLACE_WITH_THE_INTERNAL_1TB_SSD
   readlink -f "$TARGET_DISK"
   lsblk "$TARGET_DISK"
   ```

4. Create the disk layout expected by the checked-in
   `machines/work/hardware.nix`: a 1 GiB FAT32 EFI system partition labeled
   `HWCBOOT` and an ext4 root partition labeled `HWCWORK`. Keep those labels
   exact:

   ```sh
   parted --script "$TARGET_DISK" mklabel gpt
   parted --script "$TARGET_DISK" mkpart ESP fat32 1MiB 1025MiB
   parted --script "$TARGET_DISK" set 1 esp on
   parted --script "$TARGET_DISK" mkpart root ext4 1025MiB 100%
   partprobe "$TARGET_DISK"
   udevadm settle
   mkfs.fat -F 32 -n HWCBOOT "${TARGET_DISK}-part1"
   mkfs.ext4 -L HWCWORK "${TARGET_DISK}-part2"
   mount /dev/disk/by-label/HWCWORK /mnt
   mkdir -p /mnt/boot
   mount /dev/disk/by-label/HWCBOOT /mnt/boot
   findmnt /mnt
   findmnt /mnt/boot
   ```

5. Generate the hardware file, then replace only
   `/mnt/etc/nixos/configuration.nix` with the small bootstrap configuration
   below. Keep the generated `hardware-configuration.nix`. NetworkManager
   will handle Wi-Fi at the desk and wired DHCP after the move. Password SSH
   is temporary; the fleet flake later installs key-only SSH.

   ```sh
   nixos-generate-config --root /mnt
   nano /mnt/etc/nixos/configuration.nix
   ```

   ```nix
   { pkgs, ... }: {
     imports = [ ./hardware-configuration.nix ];

     boot.loader.systemd-boot.enable = true;
     boot.loader.efi.canTouchEfiVariables = true;
     hardware.enableRedistributableFirmware = true;

     networking.hostName = "hwc-work";
     networking.networkmanager.enable = true;
     networking.useDHCP = true;

     services.openssh.enable = true;
     services.openssh.settings = {
       PasswordAuthentication = true;
       PermitRootLogin = "no";
     };
     users.users.eric = {
       isNormalUser = true;
       extraGroups = [ "wheel" "networkmanager" ];
     };

     nix.settings.experimental-features = [ "nix-command" "flakes" ];
     environment.systemPackages = with pkgs; [ git ];
     system.stateVersion = "25.11";
   }
   ```

6. Install, set both passwords, remove the USB, and reboot from the SSD.
   `nixos-install` prompts for the root console password; the second command
   sets the `eric` password for the temporary SSH login. Make sure both
   commands succeed before rebooting:

   ```sh
   nixos-install --root /mnt
   nixos-enter --root /mnt -c 'passwd eric'
   reboot
   ```

7. Log in as `eric` on the installed system and run `sudo -v` with the password
   you just set. This proves local login and sudo work before any age key
   exists. The live installer's Wi-Fi connection was temporary, so join Wi-Fi
   **again** using the installed
   NetworkManager. Find the Wi-Fi IP and check SSH:

   ```sh
   sudo -v
   sudo nmtui
   nmcli device status
   ip -br address
   systemctl is-active sshd
   ```

   On the laptop, replace `WIFI_IP` with the MS-02's Wi-Fi address, then
   test a login and install the laptop's public SSH key:

   ```sh
   ssh eric@WIFI_IP
   exit
   ssh-copy-id eric@WIFI_IP
   ssh -o PasswordAuthentication=no eric@WIFI_IP hostname
   ```

   The last command must print `hwc-work`. Leave the monitor connected until
   this works. Keep the initial root password for console recovery.

## Move to the router and verify Ethernet

1. Shut down the MS-02 with `sudo poweroff`. Move it to the router and plug a
   normal Ethernet cable into its **2.5 GbE RJ45 port**. Power it on. The
   bootstrap configuration enables NetworkManager and DHCP on Ethernet.
2. On the laptop, find `hwc-work` in the router's DHCP client list and SSH to
   its **wired** IP: `ssh eric@WIRED_IP`. The Wi-Fi IP from the desk may not
   be the wired IP. On the MS-02, run `nmcli device status`, `ip -br address`,
   and `systemctl is-active sshd` to confirm the wired link and SSH.
3. If no wired DHCP lease or SSH appears, reconnect the monitor and keyboard
   and inspect those three commands locally. The installed NixOS boot entry
   and USB installer are recovery paths. Keep `hwc-server` in service.

## Before the first flake switch

The base system is now reachable over wired Ethernet without age. The fleet
flake is a second stage because its private inputs and agenix secrets need the
new host's age identity. It replaces temporary password SSH with the
repository's authorized public keys. Confirm that the laptop's public key is
among the keys in `domains/system/users/index.nix` before switching; the key
installed by `ssh-copy-id` in the bootstrap system may differ.

1. As `eric`, clone the public repo at the path used by Home Manager's repo hook
   and `hwc.paths.nixos`:

   ```sh
   git clone https://github.com/eriqueo/nixos-hwc.git /home/eric/.nixos
   nixos-version
   ```

   If the installed release is not 25.11, review `system.stateVersion` in
   `machines/work/config.nix` before the first switch. If the disk labels,
   filesystems or mounts differ from the contract above, replace
   `machines/work/hardware.nix` with the new host's generated
   `/etc/nixos/hardware-configuration.nix`, review it, and commit that change
   before building. Do not copy another host's `hardware.nix`.
2. On the new host, generate its own age identity:

   ```sh
   age_package=$(nix --extra-experimental-features 'nix-command flakes' build nixpkgs#age --no-link --print-out-paths)
   sudo install -d -m 0700 /etc/age
   sudo "$age_package/bin/age-keygen" -o /etc/age/keys.txt
   sudo chmod 0600 /etc/age/keys.txt
   sudo "$age_package/bin/age-keygen" -y /etc/age/keys.txt
   ```

   Save the printed **public** key. On the existing server, put it in
   `machines/work/AGE_PUBLIC_KEY.txt`, add `work = readKey
   ./machines/work/AGE_PUBLIC_KEY.txt;` and `work` to `allHosts` in
   `secrets.nix`, then run `sudo agenix -r -i /etc/age/keys.txt` from the
   repo. Commit and push the changed recipient rules and encrypted files.
   Pull that commit on `hwc-work`. Keep the private `/etc/age/keys.txt` off Git.

3. Before any `nixos-rebuild switch`, prove the new key can decrypt **both**
   login secrets from the pulled commit. The flake uses
   `user-initial-password.age` for `eric` and `emergency-password.age` for
   root; a declared secret is not proof it can be decrypted. Run this on
   `hwc-work` and require the final line to print:

   ```sh
   age_package=$(nix --extra-experimental-features 'nix-command flakes' build nixpkgs#age --no-link --print-out-paths)
   sudo test -s /etc/age/keys.txt &&
     sudo "$age_package/bin/age" -d -i /etc/age/keys.txt /home/eric/.nixos/domains/secrets/parts/system/user-initial-password.age >/dev/null &&
     sudo "$age_package/bin/age" -d -i /etc/age/keys.txt /home/eric/.nixos/domains/secrets/parts/system/emergency-password.age >/dev/null &&
     echo 'Both login secrets decrypt'
   ```

   If it does not print, stay on the working bootstrap system. Check that
   `work` was added to `allHosts`, all `.age` files were rekeyed, and the new
   commit was pulled. Keep the monitor and keyboard available through the
   first flake switch and reboot.

## Private flake inputs on first activation

The flake pins private GitHub inputs. The deployed base profile normally reads
their token from `/run/agenix/github-flake-token`, but a fresh generic NixOS
install has not activated agenix yet. After the rekey above, decrypt that one
secret into a root-only **temporary** file on the new host and have Nix include
it for the first build:

```sh
age_package=$(nix --extra-experimental-features 'nix-command flakes' build nixpkgs#age --no-link --print-out-paths)
sudo install -d -m 0700 /run/agenix
sudo "$age_package/bin/age" -d -i /etc/age/keys.txt /home/eric/.nixos/domains/secrets/parts/services/github-flake-token.age | sudo tee /run/agenix/github-flake-token >/dev/null
sudo chmod 0400 /run/agenix/github-flake-token
sudo test -s /run/agenix/github-flake-token
```

Pass a temporary `NIX_CONFIG` include to the first rebuild commands below.
The first declarative switch installs the base profile's permanent include,
and agenix then owns the `/run/agenix` secret. Do not paste the token into a
shell command, Git, or the Nix store.

## Build, switch and check

Confirm `/dev/disk/by-label/HWCWORK` and `/dev/disk/by-label/HWCBOOT` refer
to the mounted root and ESP, or use the reviewed generated hardware file.
Then, on `hwc-work`:

```sh
cd /home/eric/.nixos
sudo env NIX_CONFIG='!include /run/agenix/github-flake-token' nixos-rebuild build --flake .#hwc-work
sudo env NIX_CONFIG='!include /run/agenix/github-flake-token' nixos-rebuild switch --flake .#hwc-work
hostname
systemctl --failed
sudo test -s /run/agenix/user-initial-password
sudo test -s /run/agenix/emergency-password
sudo test -s /run/agenix/github-flake-token
sudo podman info >/dev/null
```

Keep this SSH session open. From a second laptop terminal, confirm key-only
login to the wired address before rebooting:

```sh
ssh -o PasswordAuthentication=no eric@WIRED_IP hostname
```

It must print `hwc-work`. Then reboot and repeat the key-only SSH check from
the laptop. On the new host, repeat the hostname, failed-unit and secret-file
checks. Then run `sudo tailscale up --hostname hwc-work` to register a separate node.
Keep `hwc-server`
running as the only owner of its existing data, jobs and public endpoints.
The new host's Tailscale IP can enter `hwc.networking.hosts.ips` once known;
the registry requires an IP for each named server.

The base Home Manager role starts the `agent-state-sync` user timer. After the
new host can SSH to `hwc-server`, run these as `eric` to set up its existing
state store:

```sh
git clone eric@hwc-server:/home/eric/git/agent-state.git ~/.agent-state
agent-state-sync link
```

Until then, the timer reports a missing clone; no state is copied by the flake.

If the first switch fails, use the console or the previous NixOS generation.
No production writer or network identity is transferred by this bootstrap.
