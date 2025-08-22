#!/bin/bash

# ==================================================
#              Configuration
# ==================================================
PROJECT="paper"
VERSION_FILE="version.yml"
JAVA_ARGS="-Xms10240M -Xmx10240M -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -XX:+ParallelRefProcEnabled -XX:+PerfDisableSharedMem -XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1HeapRegionSize=8M -XX:G1HeapWastePercent=5 -XX:G1MaxNewSizePercent=40 -XX:G1MixedGCCountTarget=4 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1NewSizePercent=30 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=15 -XX:MaxGCPauseMillis=200 -XX:MaxTenuringThreshold=1 -XX:SurvivorRatio=32 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true"

BACKUP_CONFIG="backup.yml"
LAST_BACKUP_FILE=".last_backup"

# ==================================================
#         Functions
# ==================================================

check_dependencies() {
    for cmd in curl jq yq zip sha256sum date find; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "=================================================="
            echo "Error: Required command '$cmd' not found."
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

    # Loading values from backup.yml
    MAX_BACKUPS=$(yq -r '.["Max backups"]' "$BACKUP_CONFIG")
    BACKUP_INTERVAL=$(yq -r '.["Backup interval"]' "$BACKUP_CONFIG")
    BACKUP_RETENTION=$(yq -r '.["Backup retention"]' "$BACKUP_CONFIG")
    BACKUP_DIR=$(yq -r '.["Backup directory"]' "$BACKUP_CONFIG")
    FILES=$(yq -r '.Files[]' "$BACKUP_CONFIG")
    FOLDERS=$(yq -r '.Folders[]' "$BACKUP_CONFIG")

    mkdir -p "$BACKUP_DIR"

    # --- Checking backup interval ---
    INTERVAL_SECONDS=$(parse_time_to_seconds "$BACKUP_INTERVAL")
    CURRENT_TIME=$(date +%s)
    if [ -f "$LAST_BACKUP_FILE" ]; then
        LAST_BACKUP=$(cat "$LAST_BACKUP_FILE")
    else
        LAST_BACKUP=0
    fi

    if [ $INTERVAL_SECONDS -gt 0 ] && [ $((CURRENT_TIME - LAST_BACKUP)) -lt $INTERVAL_SECONDS ]; then
        echo "Skipping backup (interval $BACKUP_INTERVAL not yet reached)."
        return
    fi

    # --- Creating new backup ---
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

    # --- Deleting old backups by count ---
    BACKUP_COUNT=$(ls -1t "$BACKUP_DIR"/*.zip 2>/dev/null | wc -l)
    if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
        DELETE_COUNT=$((BACKUP_COUNT - MAX_BACKUPS))
        echo "Too many backups, deleting $DELETE_COUNT old backup(s)..."
        ls -1t "$BACKUP_DIR"/*.zip | tail -n "$DELETE_COUNT" | xargs rm -f
    fi

    # --- Deleting old backups by retention ---
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

    echo "Rolling back with backup: $LAST_BACKUP"
    echo "Deleting current data (according to backup.yml)..."

    for f in $FILES; do
        rm -f "$f"
    done
    for d in $FOLDERS; do
        rm -rf "$d"
    done

    echo "Unpacking backup..."
    unzip -o "$LAST_BACKUP" -d . > /dev/null

    echo "Rollback complete."
}


# ==================================================
#         Main Logic
# ==================================================

# EULA-Check at first start
if [ ! -f "eula.txt" ]; then
    echo "=================================================="
    echo "Minecraft EULA"
    echo "=================================================="
    echo "Durch das Zustimmen der EULA bestätigst du, die Bedingungen zu akzeptieren."
    echo "EULA nachlesen: https://www.minecraft.net/de-de/eula"
    read -p "Stimmst du der EULA zu? (j/N): " response
    case "$response" in
        [jJ][aA]|[jJ]) 
            echo "eula=true" > eula.txt
            echo "EULA akzeptiert."
            ;;
        *)
            echo "Skript wird beendet. Du musst der EULA zustimmen, um den Server zu starten."
            exit 1
            ;;
    esac
    echo ""
fi

# Check for required dependencies
check_dependencies

# If the script is called with "backup" → only run backup
if [ "$1" == "backup" ]; then
    create_backup
    exit 0
fi

# If the script is called with "rollback" → only run rollback
if [ "$1" == "rollback" ]; then
    rollback_backup
    exit 0
fi


echo "=================================================="
echo "            Server Start                          "
echo "=================================================="
echo ""

# --- Checking for updates ---
echo "Checking for server updates for '${PROJECT}'..."
API_URL="https://api.papermc.io/v2/projects/${PROJECT}"
LATEST_VERSION=$(curl -sX GET "${API_URL}" | jq -r '.versions[-1]')

if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" == "null" ]; then
    echo "Error: Could not fetch the latest version."
else
    LATEST_BUILD=$(curl -sX GET "${API_URL}/versions/${LATEST_VERSION}" | jq -r '.builds[-1]')
    if [ -n "$LATEST_BUILD" ] && [ "$LATEST_BUILD" != "null" ]; then
        REMOTE_VERSION="${LATEST_VERSION}-${LATEST_BUILD}"

        LOCAL_VERSION="0"
        if [ -f "$VERSION_FILE" ]; then
            LOCAL_VERSION=$(grep 'version:' "$VERSION_FILE" | sed 's/version: *//' | tr -d '"' | tr -d ' ')
        fi

        echo "Installed version: ${LOCAL_VERSION:-'None'}"
        echo "Latest version:      ${REMOTE_VERSION}"

        if [ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]; then
            echo "Update available! Creating a backup before updating..."
            create_backup

            JAR_NAME="${PROJECT}-${LATEST_VERSION}-${LATEST_BUILD}.jar"
            DOWNLOAD_URL="${API_URL}/versions/${LATEST_VERSION}/builds/${LATEST_BUILD}/downloads/${JAR_NAME}"

            echo "Downloading ${JAR_NAME}..."
            curl -o "${JAR_NAME}" -L "${DOWNLOAD_URL}"

            EXPECTED_HASH=$(curl -s "${API_URL}/versions/${LATEST_VERSION}/builds/${LATEST_BUILD}" | jq -r ".downloads.application.sha256")

            if [ -s "${JAR_NAME}" ]; then
                echo "Checking integrity..."
                FILE_HASH=$(sha256sum "${JAR_NAME}" | awk '{print $1}')
                if [ "$FILE_HASH" == "$EXPECTED_HASH" ]; then
                    echo "Integrity OK. Replacing server.jar..."
                    rm -f server.jar
                    mv "${JAR_NAME}" server.jar
                    echo "version: \"${REMOTE_VERSION}\"" > "${VERSION_FILE}"
                else
                    echo "ERROR: Hash mismatch. Aborting!"
                    rm -f "${JAR_NAME}"
                    exit 1
                fi
            else
                echo "Error: Download file is corrupt or empty."
                exit 1
            fi
        else
            echo "Server is already up to date."
            # Even without an update → check if a backup is due based on interval/retention
            create_backup
        fi
    fi
fi

echo ""
echo "Starting Minecraft Server..."
java ${JAVA_ARGS} -jar server.jar nogui
