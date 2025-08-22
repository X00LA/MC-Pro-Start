#!/bin/bash

# ==================================================
#              Configuration
# ==================================================

JAVA_ARGS="-Xms10240M -Xmx10240M -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -XX:+ParallelRefProcEnabled -XX:+PerfDisableSharedMem -XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1HeapRegionSize=8M -XX:G1HeapWastePercent=5 -XX:G1MaxNewSizePercent=40 -XX:G1MixedGCCountTarget=4 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1NewSizePercent=30 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=15 -XX:MaxGCPauseMillis=200 -XX:MaxTenuringThreshold=1 -XX:SurvivorRatio=32 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true"

# Configuration files
BACKUP_CONFIG="backup.yml"
FABRIC_VERSION_FILE="fabric-version.yml"

# Internal
LAST_BACKUP_FILE=".last_backup"
MODS_DIR="mods"
FABRIC_API_SLUG="fabric-api"

# ==================================================
#         Functions
# ==================================================

check_dependencies() {
    # Added: 'java' is required for the installer.
    for cmd in curl jq yq zip sha256sum date find java; do
        if ! command -v "$cmd" &> /dev/null;
 then
            echo "=================================================="
            echo "Error: The required program '$cmd' was not found."
            echo "Please install it to use the auto-update and backup functionality."
            echo "=================================================="
            exit 1
        fi
    done
}

parse_time_to_seconds() {
    local value=$1
    if [[ $value =~ ^([0-9]+)h$ ]]; then
        echo $((${BASH_REMATCH[1]} * 3600))
    elif [[ $value =~ ^([0-9]+)d$ ]]; then
        echo $((${BASH_REMATCH[1]} * 86400))
    else
        echo 0
    fi
}

# Backup Function
create_backup() {
    if [ ! -f "$BACKUP_CONFIG" ]; then
        echo "Backup configuration file ($BACKUP_CONFIG) not found!"
        return
    fi

    # Load values from backup.yml
    MAX_BACKUPS=$(yq -r '.["Max backups"]' "$BACKUP_CONFIG")
    BACKUP_INTERVAL=$(yq -r '.["Backup interval"]' "$BACKUP_CONFIG")
    BACKUP_RETENTION=$(yq -r '.["Backup retention"]' "$BACKUP_CONFIG")
    BACKUP_DIR=$(yq -r '.["Backup directory"]' "$BACKUP_CONFIG")
    FILES=$(yq -r '.Files[]' "$BACKUP_CONFIG")
    FOLDERS=$(yq -r '.Folders[]' "$BACKUP_CONFIG")

    mkdir -p "$BACKUP_DIR"

    # --- Check backup interval ---
    INTERVAL_SECONDS=$(parse_time_to_seconds "$BACKUP_INTERVAL")
    CURRENT_TIME=$(date +%s)
    if [ -f "$LAST_BACKUP_FILE" ]; then
        LAST_BACKUP=$(cat "$LAST_BACKUP_FILE")
    else
        LAST_BACKUP=0
    fi

    if [ $INTERVAL_SECONDS -gt 0 ] && [ $((CURRENT_TIME - LAST_BACKUP)) -lt $INTERVAL_SECONDS ]; then
        echo "Backup skipped (interval $BACKUP_INTERVAL not yet reached)."
        return
    fi

    # --- Create new backup ---
    TIMESTAMP=$(date +"%y-%m-%d_%H-%M")
    COUNT=$(ls "$BACKUP_DIR"/*.zip 2>/dev/null | wc -l)
    COUNT=$((COUNT+1))
    BACKUP_NAME="${TIMESTAMP}_Backup-$(printf "%02d" $COUNT).zip"
    BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

    echo "=================================================="
    echo "Creating backup: $BACKUP_PATH"
    echo "=================================================="

    zip -r "$BACKUP_PATH" $FILES $FOLDERS > /dev/null

    echo $CURRENT_TIME > "$LAST_BACKUP_FILE"
    echo "Backup created: $BACKUP_PATH"

    # --- Delete old backups by count ---
    BACKUP_COUNT=$(ls -1t "$BACKUP_DIR"/*.zip 2>/dev/null | wc -l)
    if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
        DELETE_COUNT=$((BACKUP_COUNT - MAX_BACKUPS))
        echo "Too many backups, deleting $DELETE_COUNT old backup(s)..."
        ls -1t "$BACKUP_DIR"/*.zip | tail -n "$DELETE_COUNT" | xargs rm -f
    fi

    # --- Delete old backups by retention ---
    RETENTION_SECONDS=$(parse_time_to_seconds "$BACKUP_RETENTION")
    if [ $RETENTION_SECONDS -gt 0 ]; then
        echo "Deleting backups older than $BACKUP_RETENTION..."
        find "$BACKUP_DIR" -name "*.zip" -type f -mtime +$((RETENTION_SECONDS/86400)) -exec rm -f {} \;
    fi
}


# ==================================================
#         Rollback Function
# ==================================================

# Rollback Function
# This function restores the server to the state of the last backup.
# It deletes the current files and folders before unpacking the backup.
# Warning: This function deletes all current data based on the backup.yml configuration!
rollback_backup() {
    if [ ! -f "$BACKUP_CONFIG" ]; then
        echo "Backup configuration file ($BACKUP_CONFIG) not found!"
        return 1
    fi

    BACKUP_DIR=$(yq -r '.["Backup directory"]' "$BACKUP_CONFIG")
    FILES=$(yq -r '.Files[]' "$BACKUP_CONFIG")
    FOLDERS=$(yq -r '.Folders[]' "$BACKUP_CONFIG")

    LAST_BACKUP=$(ls -1t "$BACKUP_DIR"/*.zip 2>/dev/null | head -n1)

    if [ -z "$LAST_BACKUP" ]; then
        echo "No backup found!"
        return 1
    fi

    echo "Rollback with backup: $LAST_BACKUP"
    echo "Deleting current data (according to backup.yml)..."

    for f in $FILES;
 do
        rm -f "$f"
    done
    for d in $FOLDERS;
 do
        rm -rf "$d"
    done

    echo "Unpacking backup..."
    unzip -o "$LAST_BACKUP" -d . > /dev/null

    echo "Rollback completed."
}


# ==================================================
#         Main Logic
# ==================================================

# EULA check at the beginning
if [ ! -f "eula.txt" ]; then
    echo "=================================================="
    echo "Minecraft EULA"
    echo "=================================================="
    echo "By agreeing to the EULA, you confirm that you accept the terms."
    echo "Read EULA: https://www.minecraft.net/de-de/eula"
    read -p "Do you agree to the EULA? (Y/N): " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "eula=true" > eula.txt
            echo "EULA accepted."
            ;;
        *)
            echo "Script will be terminated. You must agree to the EULA to start the server."
            exit 1
            ;;
    esac
    echo ""
fi

# Check for required dependencies
check_dependencies

# If the script is called with "backup" → only execute backup
if [ "$1" == "backup" ]; then
    create_backup
    exit 0
fi

# If the script is called with "rollback" → only execute rollback
if [ "$1" == "rollback" ]; then
    rollback_backup
    exit 0
fi


echo "=================================================="
echo "         Fabric Server Start Script             "
echo "=================================================="
echo ""

# --- Update logic for Fabric ---
echo "Checking for Fabric server updates..."

# Get latest stable Minecraft version
MC_VERSION=$(curl -s https://meta.fabricmc.net/v2/versions/game | jq -r '[.[] | select(.stable==true)][0].version')
if [[ -z "$MC_VERSION" || "$MC_VERSION" == "null" ]]; then
    echo "Error: Could not retrieve the latest Minecraft version from the Fabric API."
    exit 1
fi

# Get latest Fabric Loader version for MC_VERSION
LOADER_JSON=$(curl -s "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}")

if [[ -z "$LOADER_JSON" || "$LOADER_JSON" == "[]" ]]; then
    echo "Error: Could not find any Fabric Loader version for Minecraft ${MC_VERSION}."
    exit 1
fi

# Check the structure of the Loader JSON response
LOADER_VERSION=$(echo "$LOADER_JSON" | jq -r '.[0].loader.version // empty')

# Check if the Loader version was successfully retrieved
if [[ -z "$LOADER_VERSION" ]]; then
    echo "Error: Could not retrieve the Loader version."
    exit 1
fi

# Read local versions from YAML file
LOCAL_MC_VERSION="0"
LOCAL_LOADER_VERSION="0"
if [ -f "$FABRIC_VERSION_FILE" ]; then
    LOCAL_MC_VERSION=$(yq -r '.minecraft' "$FABRIC_VERSION_FILE" 2>/dev/null)
    LOCAL_LOADER_VERSION=$(yq -r '.loader' "$FABRIC_VERSION_FILE" 2>/dev/null)
fi

echo "Installed version: MC ${LOCAL_MC_VERSION:-'None'} / Loader ${LOCAL_LOADER_VERSION:-'None'}"
echo "Latest version:      MC ${MC_VERSION} / Loader ${LOADER_VERSION}"

# Compare versions and perform update if necessary
if [[ "$LOCAL_MC_VERSION" != "$MC_VERSION" || "$LOCAL_LOADER_VERSION" != "$LOADER_VERSION" ]]; then
    echo "Update available! Performing update..."
    create_backup

    # Download Fabric Installer
    INSTALLER_URL=$(curl -s https://meta.fabricmc.net/v2/versions/installer | jq -r 'map(.url)[0]')
    if [[ -z "$INSTALLER_URL" || "$INSTALLER_URL" == "null" ]]; then
        echo "Error: Could not retrieve the URL for the Fabric Installer."
        exit 1
    fi
    INSTALLER_JAR="fabric-installer.jar"
    echo "Downloading Fabric Installer..."
    curl -o "$INSTALLER_JAR" -L "$INSTALLER_URL"

    if [ ! -f "$INSTALLER_JAR" ]; then
        echo "Error: Download of Fabric Installer failed."
        exit 1
    fi

    # Execute installer to create/update the server
    echo "Executing Fabric Installer for Minecraft ${MC_VERSION}..."
    java -jar "$INSTALLER_JAR" server -mcversion "$MC_VERSION" -downloadMinecraft
    rm "$INSTALLER_JAR" # Delete the installer after use

    # Download the appropriate Fabric API Mod from Modrinth
    echo "Updating Fabric API Mod..."
    mkdir -p "$MODS_DIR"
    # Delete old versions of Fabric API to avoid conflicts
    find "$MODS_DIR" -name "fabric-api-*.jar" -type f -delete
    
    # Make API call to Modrinth
    response=$(curl -G -s "https://api.modrinth.com/v2/project/${FABRIC_API_SLUG}/version" \
        --data-urlencode "game_versions=[\"${MC_VERSION}\"]" \
        --data-urlencode "loaders=[\"fabric\"]")

    # Check API response
    if [ -z "$response" ]; then
    echo "Error: No response received from the API."
    exit 1
    fi

    # Get download URL for the latest compatible version
    download_url=$(echo "$response" | jq -r '.[0].files[0].url')

    # Check if download URL was successfully extracted
    if [ -z "$download_url" ]; then
    echo "Error: No download URL found."
    exit 1
    fi

    # Download the file
    echo "Downloading Fabric API from $download_url..."
    curl -L "$download_url" -o "$MODS_DIR/fabric-api.jar"

    echo "Download completed and saved to $MODS_DIR/fabric-api.jar."

    # Write new versions to tracking file
    echo "minecraft: ${MC_VERSION}" > "$FABRIC_VERSION_FILE"
    echo "loader: ${LOADER_VERSION}" >> "$FABRIC_VERSION_FILE"
    echo "Update completed."
else
    echo "Server is already up to date."
    # Still perform backup check if due by interval
    create_backup 
fi

echo ""
echo "Starting Minecraft Fabric Server..."
if [ ! -f "fabric-server-launch.jar" ]; then
    echo "ERROR: fabric-server-launch.jar not found! The server cannot be started."
    echo "Run the script again to attempt installation."
    exit 1
fi
java ${JAVA_ARGS} -jar fabric-server-launch.jar nogui
