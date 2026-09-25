# Navidrome admin password

The encrypted password is `navidrome-admin-password.age`. The secrets generator
mounts it at `/run/agenix/navidrome-admin-password` on fleet hosts.

To rotate it, replace the encrypted payload using the recipients in the root
`secrets.nix`, verify decryption with a host identity, then activate the server.
Keep password values out of this directory's documentation and Git history.
