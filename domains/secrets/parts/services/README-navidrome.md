# Navidrome Password Secret Setup

## Current Status
The Navidrome admin password has been moved from plaintext configuration to an agenix secret for improved security.

## Required Action
You need to create the encrypted secret file `navidrome-admin-password.age` with your desired password.

### Steps to Create the Secret

1. **Ensure you have age installed:**
   ```bash
   nix-shell -p age
   ```

2. **Create the encrypted secret:**
   ```bash
   cd /home/eric/.nixos/domains/secrets/parts/server/

   # Replace 'your-secure-password-here' with your actual password
   # Use a strong password - the old password was: il0wwlm?
   echo -n 'your-secure-password-here' | age -R /etc/age/keys.txt.pub > navidrome-admin-password.age
   ```

3. **Verify the secret file was created:**
   ```bash
   ls -la navidrome-admin-password.age
   # Should show a file with restricted permissions
   ```

4. **Delete the template file (if exists):**
   ```bash
   rm -f navidrome-admin-password.age.TEMPLATE
   ```

5. **Rebuild your system:**
   ```bash
   sudo nixos-rebuild switch --flake .#hwc-server
   ```

## Security Notes

- The old hardcoded password (`il0wwlm?`) was visible in the configuration files
- Consider using a different, more secure password when creating the secret
- The secret file will be automatically decrypted at runtime by agenix
- Never commit unencrypted passwords to git

## Troubleshooting

If you get an error about missing age keys:
```bash
# Ensure age keys exist
sudo ls -la /etc/age/keys.txt
```

If the keys don't exist, you'll need to generate them:
```bash
sudo mkdir -p /etc/age
sudo age-keygen -o /etc/age/keys.txt
sudo age-keygen -y /etc/age/keys.txt > /etc/age/keys.txt.pub
```
