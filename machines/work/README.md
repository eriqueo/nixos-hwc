# hwc-work: first NixOS switch on the MS-02

`#hwc-work` is the staged work-server output in the fleet flake. It provides the
existing headless CLI/Home Manager setup, SSH, Tailscale, Podman and server tools.
It leaves CouchDB, Nightly Builds, Refinery, business services, public routes and
storage mounts on `hwc-server`. No production data is copied by activating it.

## Before the first switch

1. Install NixOS **25.11** on the MS-02 with UEFI. The checked-in
   `hardware.nix` expects one ext4 root partition labeled `HWCWORK` and one
   FAT32 EFI system partition labeled `HWCBOOT`, mounted at `/` and `/boot`.
   Use the NixOS installer to identify the actual SSD before partitioning.
   If you installed with different labels, filesystems or partitions, replace
   `machines/work/hardware.nix` with the new host's generated
   `/etc/nixos/hardware-configuration.nix`, review it, and commit that change
   before building. Do not copy another host's `hardware.nix`.
2. Create the `eric` wheel user during the initial install. Keep console access
   and the initial root password until SSH and agenix work after a reboot.
   Confirm the chosen 2.5 GbE port has network access.
3. As `eric`, clone the public repo at the path used by Home Manager's repo hook
   and `hwc.paths.nixos`:

   ```sh
   git clone https://github.com/eriqueo/nixos-hwc.git /home/eric/.nixos
   ```

   Check the installed release with `nixos-version`; if it is not 25.11,
   review `system.stateVersion` in `machines/work/config.nix` before the first
   switch.
4. On the new host, generate its own age identity:

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
sudo test -s /run/agenix/github-flake-token
sudo podman info >/dev/null
```

Reboot, repeat the hostname, failed-unit and SSH checks from another device,
then run `sudo tailscale up --hostname hwc-work` to register a separate node.
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
