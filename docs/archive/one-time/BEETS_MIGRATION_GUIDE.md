# Migrating from Containerized to Native Beets

## Current Situation

Your beets is running in a container (LinuxServer.io image) which makes it complicated to use:
- Can't run `beet` commands directly on host
- Requires wrapper scripts to exec into container
- Helper scripts don't work as expected
- More complexity and potential for errors

## Better Approach: Native Installation

Install beets directly on the host system using NixOS packages.

## Migration Steps

### 1. Backup Current Database

```bash
# Backup the container's database
sudo cp -r /opt/downloads/beets /opt/downloads/beets-container-backup
```

### 2. Disable Container, Enable Native

In your NixOS configuration, find where beets container is enabled (likely `profiles/server.nix` or `machines/hwc-server/config.nix`) and change:

```nix
# OLD - Disable this
hwc.server.containers.beets.enable = false;  # or comment out

# NEW - Enable this instead
hwc.server.beets-native.enable = true;
```

### 3. Rebuild

```bash
sudo nixos-rebuild switch --flake .#hwc-server
```

This will:
- ✅ Install beets on the host with all plugins
- ✅ Create config at `/home/eric/.config/beets/config.yaml`
- ✅ Set up database at `/var/lib/beets/library.db`
- ✅ Start beets web service at port 8337
- ✅ Make `beet` command available system-wide

### 4. Import Existing Library

```bash
# Import your existing music library into the new database
beet import -L /mnt/media/music
```

This will scan your existing files and add them to the database without moving them.

### 5. Verify

```bash
# These now work directly:
beet stats -e
beet ls artist:Ween
beet duplicates -k

# Helper script works without wrapper:
./workspace/utilities/beets-helper.sh analyze-library
```

### 6. Remove Old Container (Optional)

Once verified working:

```bash
# Stop and remove container
sudo systemctl stop podman-beets
sudo systemctl disable podman-beets

# Remove old database (after confirming new one works!)
sudo rm -rf /opt/downloads/beets-container-backup
```

## Benefits of Native Installation

✅ **Simple**: Run `beet` commands directly, no container wrapper needed
✅ **Fast**: No container overhead
✅ **Integrated**: Works seamlessly with NixOS system
✅ **Maintainable**: Declarative configuration in Nix
✅ **Scripts work**: Helper scripts work as designed
✅ **Easy to use**: Natural command-line workflow

## Configuration

The native setup uses the same configuration as the container:
- Same plugins enabled
- Same import settings
- Same path formats
- Same matching thresholds
- Web interface on same port (8337)

But it's now:
- Declared in Nix (version controlled)
- Easily modifiable
- No container complexity

## Rollback

If you need to go back to the container:

```bash
# Re-enable container
hwc.server.containers.beets.enable = true;
hwc.server.beets-native.enable = false;

# Rebuild
sudo nixos-rebuild switch --flake .#hwc-server

# Restore backup
sudo cp -r /opt/downloads/beets-container-backup/* /opt/downloads/beets/
```

---

**Recommendation:** Migrate to native installation for simpler, more maintainable setup.
