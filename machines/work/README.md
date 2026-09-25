# hwc-work: MS-02 fleet host and work-server rollout

`#hwc-work` is the active work-server output in the fleet flake. It provides the
existing headless CLI/Home Manager setup, SSH, Tailscale, Podman and server tools.
It leaves CouchDB, Nightly Builds, Refinery, business services, public routes and
storage mounts on `hwc-server`. No production data is copied by activating it.

## Installed system: preserve Windows and Wi-Fi

The MS-02 already boots NixOS 25.11 alongside Windows on its internal SSD.
Do not repartition or format this disk. Linux uses these existing partitions:

| Partition | Label | Use |
| --- | --- | --- |
| nvme0n1p1 | SYSTEM | Windows EFI; leave unchanged |
| nvme0n1p2 | — | Windows reserved; leave unchanged |
| nvme0n1p3 | Windows | Windows installation; leave unchanged |
| nvme0n1p4 | Recovery | Windows recovery; leave unchanged |
| nvme0n1p5 | HWCBOOT | Linux EFI, mounted at /boot |
| nvme0n1p6 | HWCWORK | Linux ext4 root, mounted at / |

The generated hardware configuration is `/etc/nixos/hardware-configuration.nix`.
The fleet hardware file keeps the verified labels and the generated initrd,
Intel microcode and NPU settings. Windows retains its separate EFI partition;
use the firmware boot menu to select it. Windows boot has not been exercised
as part of the Linux cutover.

NetworkManager has a persistent `Pupcastle` Wi-Fi profile on `wlo5`. Keep that
profile through activation. Ethernet is optional. The observed Wi-Fi address was
`192.168.0.231`; check DHCP if it changes. Keep the old server on its existing
network and leave its production services and DAS in place.

Before activation, check the actual mounts, connectivity and administrator access:

```sh
hostname
lsblk -f
findmnt /
findmnt /boot
nmcli device status
sudo -v
```

From the old server, require a key-only SSH login to the current Wi-Fi address.
The fleet's authorized keys must include the key used for that login. Keep console
access available through the first switch and reboot. Retain the bootstrap NixOS
generation as the rollback target.

## Before the first flake switch

The base system is reachable over Wi-Fi without age. The fleet
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
   filesystems or mounts differ from the verified layout above, review
   `machines/work/hardware.nix` against the new host's generated
   `/etc/nixos/hardware-configuration.nix`, and commit any required change
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
sudo install -d -m 0700 /run/hwc-work-bootstrap
sudo "$age_package/bin/age" -d -i /etc/age/keys.txt /home/eric/.nixos/domains/secrets/parts/services/github-flake-token.age | sudo tee /run/hwc-work-bootstrap/github-flake-token >/dev/null
sudo chmod 0400 /run/hwc-work-bootstrap/github-flake-token
sudo test -s /run/hwc-work-bootstrap/github-flake-token
```

Pass a temporary `NIX_CONFIG` include to the first rebuild commands below.
The first declarative switch installs the base profile's permanent include,
and agenix then owns the `/run/agenix` secret. Keep the temporary file outside
`/run/agenix`: activation needs to create that path as a symlink. Remove the
temporary token after successful activation. Do not paste the token into a
shell command, Git, or the Nix store.

## Build, switch and check

Confirm `/dev/disk/by-label/HWCWORK` and `/dev/disk/by-label/HWCBOOT` refer
to the mounted root and ESP, or use the reviewed generated hardware file.
Then, on `hwc-work`:

```sh
cd /home/eric/.nixos
sudo env NIX_CONFIG='!include /run/hwc-work-bootstrap/github-flake-token' nixos-rebuild build --flake .#hwc-work
sudo env NIX_CONFIG='!include /run/hwc-work-bootstrap/github-flake-token' nixos-rebuild switch --flake .#hwc-work
hostname
systemctl --failed
sudo test -s /run/agenix/user-initial-password
sudo test -s /run/agenix/emergency-password
sudo test -s /run/agenix/github-flake-token
sudo podman info >/dev/null
```

Keep this SSH session open. From a second laptop terminal, confirm key-only
login to the current Wi-Fi address before rebooting:

```sh
ssh -o PasswordAuthentication=no eric@WIFI_IP hostname
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
