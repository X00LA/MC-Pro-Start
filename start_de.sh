#!/bin/bash

# ==================================================
#              Konfiguration
# ==================================================
PROJECT="paper"
VERSION_FILE="version.yml"
JAVA_ARGS="-Xms10240M -Xmx10240M -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -XX:+ParallelRefProcEnabled -XX:+PerfDisableSharedMem -XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1HeapRegionSize=8M -XX:G1HeapWastePercent=5 -XX:G1MaxNewSizePercent=40 -XX:G1MixedGCCountTarget=4 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1NewSizePercent=30 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=15 -XX:MaxGCPauseMillis=200 -XX:MaxTenuringThreshold=1 -XX:SurvivorRatio=32 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true"

BACKUP_CONFIG="backup.yml"
LAST_BACKUP_FILE=".last_backup"

# ==================================================
#         Funktionen
# ==================================================

check_dependencies() {
    for cmd in curl jq yq zip sha256sum date find; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "=================================================="
            echo "Fehler: Das erforderliche Programm '$cmd' wurde nicht gefunden."
            echo "Bitte installiere es, um die Auto-Update- und Backup-Funktion zu nutzen."
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

# Backup-Funktion
create_backup() {
    if [ ! -f "$BACKUP_CONFIG" ]; then
        echo "Backup-Konfigurationsdatei ($BACKUP_CONFIG) nicht gefunden!"
        return
    fi

    # Werte aus backup.yml laden
    MAX_BACKUPS=$(yq -r '.["Max backups"]' "$BACKUP_CONFIG")
    BACKUP_INTERVAL=$(yq -r '.["Backup interval"]' "$BACKUP_CONFIG")
    BACKUP_RETENTION=$(yq -r '.["Backup retention"]' "$BACKUP_CONFIG")
    BACKUP_DIR=$(yq -r '.["Backup directory"]' "$BACKUP_CONFIG")
    FILES=$(yq -r '.Files[]' "$BACKUP_CONFIG")
    FOLDERS=$(yq -r '.Folders[]' "$BACKUP_CONFIG")

    mkdir -p "$BACKUP_DIR"

    # --- Backup Interval prüfen ---
    INTERVAL_SECONDS=$(parse_time_to_seconds "$BACKUP_INTERVAL")
    CURRENT_TIME=$(date +%s)
    if [ -f "$LAST_BACKUP_FILE" ]; then
        LAST_BACKUP=$(cat "$LAST_BACKUP_FILE")
    else
        LAST_BACKUP=0
    fi

    if [ $INTERVAL_SECONDS -gt 0 ] && [ $((CURRENT_TIME - LAST_BACKUP)) -lt $INTERVAL_SECONDS ]; then
        echo "Backup wird übersprungen (Intervall $BACKUP_INTERVAL noch nicht erreicht)."
        return
    fi

    # --- Neues Backup erstellen ---
    TIMESTAMP=$(date +"%y-%m-%d_%H-%M")
    COUNT=$(ls "$BACKUP_DIR"/*.zip 2>/dev/null | wc -l)
    COUNT=$((COUNT+1))
    BACKUP_NAME="${TIMESTAMP}_Backup-$(printf "%02d" $COUNT).zip"
    BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

    echo "=================================================="
    echo "Erstelle Backup: $BACKUP_PATH"
    echo "=================================================="

    zip -r "$BACKUP_PATH" $FILES $FOLDERS > /dev/null

    echo $CURRENT_TIME > "$LAST_BACKUP_FILE"
    echo "Backup erstellt: $BACKUP_PATH"

    # --- Alte Backups nach Anzahl löschen ---
    BACKUP_COUNT=$(ls -1t "$BACKUP_DIR"/*.zip 2>/dev/null | wc -l)
    if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
        DELETE_COUNT=$((BACKUP_COUNT - MAX_BACKUPS))
        echo "Zu viele Backups, lösche $DELETE_COUNT alte Backup(s)..."
        ls -1t "$BACKUP_DIR"/*.zip | tail -n "$DELETE_COUNT" | xargs rm -f
    fi

    # --- Alte Backups nach Retention löschen ---
    RETENTION_SECONDS=$(parse_time_to_seconds "$BACKUP_RETENTION")
    if [ $RETENTION_SECONDS -gt 0 ]; then
        echo "Lösche Backups älter als $BACKUP_RETENTION..."
        find "$BACKUP_DIR" -name "*.zip" -type f -mtime +$((RETENTION_SECONDS/86400)) -exec rm -f {} \;
    fi
}


# ==================================================
#         Rollback-Funktion
# ==================================================

# Rollback-Funktion
# Diese Funktion stellt den Server auf den Zustand des letzten Backups zurück.
# Sie löscht die aktuellen Dateien und Ordner, bevor das Backup entpackt wird.
# Achtung: Diese Funktion löscht alle aktuellen Daten anhand der backup.yml-Konfiguration!
rollback_backup() {
    if [ ! -f "$BACKUP_CONFIG" ]; then
        echo "Backup-Konfigurationsdatei ($BACKUP_CONFIG) nicht gefunden!"
        return 1
    fi

    BACKUP_DIR=$(yq -r '.["Backup directory"]' "$BACKUP_CONFIG")
    FILES=$(yq -r '.Files[]' "$BACKUP_CONFIG")
    FOLDERS=$(yq -r '.Folders[]' "$BACKUP_CONFIG")

    LAST_BACKUP=$(ls -1t "$BACKUP_DIR"/*.zip 2>/dev/null | head -n1)

    if [ -z "$LAST_BACKUP" ]; then
        echo "Kein Backup gefunden!"
        return 1
    fi

    echo "Rollback mit Backup: $LAST_BACKUP"
    echo "Lösche aktuelle Daten (laut backup.yml)..."

    for f in $FILES; do
        rm -f "$f"
    done
    for d in $FOLDERS; do
        rm -rf "$d"
    done

    echo "Entpacke Backup..."
    unzip -o "$LAST_BACKUP" -d . > /dev/null

    echo "Rollback abgeschlossen."
}


# ==================================================
#         Hauptlogik
# ==================================================
check_dependencies

# Falls das Skript mit "backup" aufgerufen wird → nur Backup ausführen
if [ "$1" == "backup" ]; then
    create_backup
    exit 0
fi

# Falls das Skript mit "rollback" aufgerufen wird → nur Rollback ausführen
if [ "$1" == "rollback" ]; then
    rollback_backup
    exit 0
fi


echo "=================================================="
echo "            GooberGuild-SMP1 Server Start         "
echo "=================================================="
echo ""

# --- Update prüfen ---
echo "Prüfe auf Server-Updates für '${PROJECT}'..."
API_URL="https://api.papermc.io/v2/projects/${PROJECT}"
LATEST_VERSION=$(curl -sX GET "${API_URL}" | jq -r '.versions[-1]')

if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" == "null" ]; then
    echo "Fehler: Konnte die neueste Version nicht abrufen."
else
    LATEST_BUILD=$(curl -sX GET "${API_URL}/versions/${LATEST_VERSION}" | jq -r '.builds[-1]')
    if [ -n "$LATEST_BUILD" ] && [ "$LATEST_BUILD" != "null" ]; then
        REMOTE_VERSION="${LATEST_VERSION}-${LATEST_BUILD}"

        LOCAL_VERSION="0"
        if [ -f "$VERSION_FILE" ]; then
            LOCAL_VERSION=$(grep 'version:' "$VERSION_FILE" | sed 's/version: *//' | tr -d '"' | tr -d ' ')
        fi

        echo "Installierte Version: ${LOCAL_VERSION:-'Keine'}"
        echo "Neueste Version:      ${REMOTE_VERSION}"

        if [ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]; then
            echo "Update verfügbar! Vor Update wird ein Backup erstellt..."
            create_backup

            JAR_NAME="${PROJECT}-${LATEST_VERSION}-${LATEST_BUILD}.jar"
            DOWNLOAD_URL="${API_URL}/versions/${LATEST_VERSION}/builds/${LATEST_BUILD}/downloads/${JAR_NAME}"

            echo "Lade ${JAR_NAME} herunter..."
            curl -o "${JAR_NAME}" -L "${DOWNLOAD_URL}"

            EXPECTED_HASH=$(curl -s "${API_URL}/versions/${LATEST_VERSION}/builds/${LATEST_BUILD}" | jq -r ".downloads.application.sha256")

            if [ -s "${JAR_NAME}" ]; then
                echo "Prüfe Integrität..."
                FILE_HASH=$(sha256sum "${JAR_NAME}" | awk '{print $1}')
                if [ "$FILE_HASH" == "$EXPECTED_HASH" ]; then
                    echo "Integrität OK. Ersetze server.jar..."
                    rm -f server.jar
                    mv "${JAR_NAME}" server.jar
                    echo "version: \"${REMOTE_VERSION}\"" > "${VERSION_FILE}"
                else
                    echo "FEHLER: Hash stimmt nicht überein. Abbruch!"
                    rm -f "${JAR_NAME}"
                    exit 1
                fi
            else
                echo "Fehler: Download-Datei fehlerhaft."
                exit 1
            fi
        else
            echo "Server ist bereits aktuell."
            # Auch ohne Update → prüfen, ob nach Intervall/Retention ein Backup fällig ist
            create_backup
        fi
    fi
fi

echo ""
echo "Starte Minecraft Server..."
java ${JAVA_ARGS} -jar server.jar nogui
