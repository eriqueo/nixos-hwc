# Shared *arr application configuration enforcement
# Ensures config.xml has correct authentication and URL settings
# Also ensures default admin user exists in database for Basic auth
{ lib, pkgs }:

{
  # Generate a script that enforces correct config.xml settings for arr apps
  # Usage: mkArrConfigScript { name = "radarr"; configPath = "/path/to/config"; urlBase = "/radarr"; }
  mkArrConfigScript = { name, configPath, urlBase }:
    let
      instanceName = lib.toUpper (lib.substring 0 1 name) + lib.substring 1 (lib.stringLength name - 1) name;
      sqlite = "${pkgs.sqlite}/bin/sqlite3";
    in
    pkgs.writeShellScript "enforce-${name}-config" ''
      CONFIG_FILE="${configPath}/config.xml"
      DB_FILE="${configPath}/${name}.db"

      # Wait for config directory to exist
      mkdir -p "${configPath}"

      # If config.xml doesn't exist, create a minimal one
      if [ ! -f "$CONFIG_FILE" ]; then
        echo "Creating initial config.xml for ${name}"
        cat > "$CONFIG_FILE" << 'INITEOF'
<Config>
  <BindAddress>*</BindAddress>
  <Port>8989</Port>
  <SslPort>9898</SslPort>
  <EnableSsl>False</EnableSsl>
  <LaunchBrowser>True</LaunchBrowser>
  <AuthenticationMethod>Basic</AuthenticationMethod>
  <AuthenticationRequired>DisabledForLocalAddresses</AuthenticationRequired>
  <Branch>main</Branch>
  <LogLevel>info</LogLevel>
  <UrlBase>${urlBase}</UrlBase>
  <InstanceName>${instanceName}</InstanceName>
  <UpdateMechanism>Docker</UpdateMechanism>
</Config>
INITEOF
        chown 1000:100 "$CONFIG_FILE"
        chmod 644 "$CONFIG_FILE"
      fi

      # Enforce correct settings using xmlstarlet if available, otherwise use sed
      if command -v xmlstarlet &> /dev/null; then
        # Use xmlstarlet for proper XML manipulation
        xmlstarlet ed -L \
          -u "/Config/AuthenticationMethod" -v "Basic" \
          -u "/Config/AuthenticationRequired" -v "DisabledForLocalAddresses" \
          -u "/Config/UrlBase" -v "${urlBase}" \
          "$CONFIG_FILE" 2>/dev/null || true
      else
        # Fallback: Use sed for simple replacements
        ${pkgs.gnused}/bin/sed -i \
          -e 's|<AuthenticationMethod>[^<]*</AuthenticationMethod>|<AuthenticationMethod>Basic</AuthenticationMethod>|' \
          -e 's|<AuthenticationRequired>[^<]*</AuthenticationRequired>|<AuthenticationRequired>DisabledForLocalAddresses</AuthenticationRequired>|' \
          -e 's|<UrlBase>[^<]*</UrlBase>|<UrlBase>${urlBase}</UrlBase>|' \
          "$CONFIG_FILE"
      fi

      # Ensure admin user exists in database for Basic auth
      # Uses shared password hash so all arr apps have same credentials
      if [ -f "$DB_FILE" ]; then
        USER_COUNT=$(${sqlite} "$DB_FILE" "SELECT COUNT(*) FROM Users WHERE Username='admin';" 2>/dev/null || echo "0")
        if [ "$USER_COUNT" = "0" ]; then
          echo "Adding admin user to ${name} database..."
          ${sqlite} "$DB_FILE" "INSERT INTO Users (Id, Identifier, Username, Password, Salt, Iterations) VALUES (1, 'e0863aab-c937-46c4-a12c-7893ad6c7ead', 'admin', 'Ogam5ghRJLX6CMlV3oG8EDroqjE7inIFxc/FpHkYE7Y=', 'SmqSFRDq5NUhjDfvFnuDNQ==', 10000);" 2>/dev/null || true
          chown 1000:100 "$DB_FILE"
        fi
      fi

      echo "${name} config enforced: AuthenticationMethod=Basic, AuthenticationRequired=DisabledForLocalAddresses, UrlBase=${urlBase}"
    '';
}
