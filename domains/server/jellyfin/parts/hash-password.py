#!/usr/bin/env python3
import sys
import hashlib
import secrets

def hash_password(password):
    """Hash password using Jellyfin's PBKDF2-SHA1 format"""
    # Generate 16-byte random salt
    salt = secrets.token_bytes(16)
    salt_hex = salt.hex()

    # PBKDF2-SHA1 with 10000 iterations
    iterations = 10000
    hash_bytes = hashlib.pbkdf2_hmac('sha1', password.encode('utf-8'), salt, iterations)
    hash_hex = hash_bytes.hex()

    # Jellyfin format: pbkdf2-sha1$iterations$salt$hash
    return f"pbkdf2-sha1${iterations}${salt_hex}${hash_hex}"

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: hash-password.py <password>", file=sys.stderr)
        sys.exit(1)

    password = sys.argv[1]
    print(hash_password(password))
