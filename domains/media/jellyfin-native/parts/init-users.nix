{ pkgs, config }:

pkgs.writeShellScript "jellyfin-init-users" ''
  set -euo pipefail

  DB_PATH="/var/lib/hwc/jellyfin/data/jellyfin.db"
  ADMIN_PASSWORD_FILE="${config.age.secrets.jellyfin-admin-password.path}"
  ERIC_PASSWORD_FILE="${config.age.secrets.jellyfin-eric-password.path}"

  # Wait for database to be created if it doesn't exist yet
  # (First boot: Jellyfin needs to create it, subsequent boots: already exists)
  MAX_WAIT=5
  WAITED=0
  while [ ! -f "$DB_PATH" ] && [ $WAITED -lt $MAX_WAIT ]; do
    echo "Waiting for Jellyfin database to exist..."
    sleep 1
    WAITED=$((WAITED + 1))
  done

  # If database doesn't exist, this is first boot - skip initialization
  # Jellyfin will create it and we'll set passwords on next restart
  if [ ! -f "$DB_PATH" ]; then
    echo "Database doesn't exist yet (first boot), skipping user initialization"
    echo "Users will be initialized on next service restart"
    exit 0
  fi

  # Function to hash password using Jellyfin's PBKDF2-SHA1 format
  hash_password() {
    local password="$1"
    ${pkgs.python3}/bin/python3 ${./hash-password.py} "$password"
  }

  # Function to ensure user exists with correct password
  ensure_user() {
    local username="$1"
    local password_file="$2"

    local password=$(cat "$password_file")
    local password_hash=$(hash_password "$password")

    # Check if user exists
    local user_exists=$(${pkgs.sqlite}/bin/sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM Users WHERE Username='$username';")

    if [ "$user_exists" -eq 0 ]; then
      echo "Creating user: $username"
      local user_id=$(${pkgs.util-linux}/bin/uuidgen)
      ${pkgs.sqlite}/bin/sqlite3 "$DB_PATH" <<SQL
INSERT INTO Users (
  Id, Username, Password, EnableLocalPassword,
  InternalId, MaxActiveSessions, MaxParentalAgeRating,
  EnableAutoLogin, EnableNextEpisodeAutoPlay, EnableUserPreferenceAccess,
  DisplayCollectionsView, DisplayMissingEpisodes, HidePlayedInLatest,
  PlayDefaultAudioTrack, RememberAudioSelections, RememberSubtitleSelections,
  SubtitleMode, SyncPlayAccess, MustUpdatePassword,
  InvalidLoginAttemptCount, AuthenticationProviderId, PasswordResetProviderId,
  RowVersion
) VALUES (
  '$user_id', '$username', '$password_hash', 1,
  (SELECT COALESCE(MAX(InternalId), 0) + 1 FROM Users), 0, NULL,
  0, 1, 1,
  1, 0, 1,
  1, 1, 1,
  0, 0, 0,
  0, 'Jellyfin.Server.Implementations.Users.DefaultAuthenticationProvider', 'Jellyfin.Server.Implementations.Users.DefaultPasswordResetProvider',
  1
);
SQL
      echo "User $username created successfully"
    else
      echo "User $username already exists, updating password..."
      ${pkgs.sqlite}/bin/sqlite3 "$DB_PATH" "UPDATE Users SET Password='$password_hash', EnableLocalPassword=1 WHERE Username='$username';"
      echo "Password updated for user: $username"
    fi
  }

  # Ensure admin user exists
  echo "Ensuring admin user..."
  ensure_user "admin" "$ADMIN_PASSWORD_FILE"

  # Ensure eric user exists
  echo "Ensuring eric user..."
  ensure_user "eric" "$ERIC_PASSWORD_FILE"

  echo "User initialization complete"
''
