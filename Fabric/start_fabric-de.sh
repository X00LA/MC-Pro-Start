#!/bin/bash

# ==================================================
#              Konfiguration
# ==================================================

JAVA_ARGS="-Xms10240M -Xmx10240M -XX:+AlwaysPreTouch -XX:+DisableExplicitGC -XX:+ParallelRefProcEnabled -XX:+PerfDisableSharedMem -XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1HeapRegionSize=8M -XX:G1HeapWastePercent=5 -XX:G1MaxNewSizePercent=40 -XX:G1MixedGCCountTarget=4 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1NewSizePercent=30 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:G1ReservePercent=20 -XX:InitiatingHeapOccupancyPercent=15 -XX:MaxGCPauseMillis=200 -XX:MaxTenuringThreshold=1 -XX:SurvivorRatio=32 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true"

# Konfigurationsdateien
BACKUP_CONFIG="backup.yml"
FABRIC_VERSION_FILE="fabric-version.yml"

# Interna
LAST_BACKUP_FILE=".last_backup"
MODS_DIR="mods"
FABRIC_API_SLUG="fabric-api"

# ==================================================
#         Funktionen
# ==================================================

check_dependencies() {
    # Hinzugefügt: 'java' wird für den Installer benötigt.
    for cmd in curl jq yq zip sha256sum date find java; do
        if ! command -v "$cmd" &> /dev/null;
 then
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

    for f in $FILES;
 do
        rm -f "$f"
    done
    for d in $FOLDERS;
 do
        rm -rf "$d"
    done

    echo "Entpacke Backup..."
    unzip -o "$LAST_BACKUP" -d . > /dev/null

    echo "Rollback abgeschlossen."
}


# ==================================================
#         Hauptlogik
# ==================================================

# EULA-Prüfung zu Beginn
if [ ! -f "eula.txt" ]; then
    echo "=================================================="
    echo "Minecraft EULA"
    echo "=================================================="
    echo "Durch das Zustimmen der EULA bestätigst du, die Bedingungen zu akzeptieren."
    echo "EULA nachlesen: https://www.minecraft.net/de-de/eula"
    read -p "Stimmst du der EULA zu? (J/N): " response
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

# Prüfe auf erforderliche Abhängigkeiten
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
echo "         Fabric Server Start-Skript             "
echo "=================================================="
echo ""

# --- Update-Logik für Fabric ---
echo "Prüfe auf Fabric-Server-Updates..."

# Hole neueste stabile Minecraft-Version
MC_VERSION=$(curl -s https://meta.fabricmc.net/v2/versions/game | jq -r '[.[] | select(.stable==true)][0].version')
if [[ -z "$MC_VERSION" || "$MC_VERSION" == "null" ]]; then
    echo "Fehler: Konnte die neueste Minecraft-Version nicht von der Fabric-API abrufen."
    exit 1
fi

# Hole neueste Fabric Loader Version für die MC_VERSION
LOADER_JSON=$(curl -s "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}")

if [[ -z "$LOADER_JSON" || "$LOADER_JSON" == "[]" ]]; then
    echo "Fehler: Konnte keine Fabric Loader Version für Minecraft ${MC_VERSION} finden."
    exit 1
fi

# Überprüfe die Struktur der Loader JSON-Antwort
LOADER_VERSION=$(echo "$LOADER_JSON" | jq -r '.[0].loader.version // empty')

# Überprüfe, ob die Loader-Version erfolgreich abgerufen wurde
if [[ -z "$LOADER_VERSION" ]]; then
    echo "Fehler: Konnte die Loader-Version nicht abrufen."
    exit 1
fi

# Lese lokale Versionen aus der YAML-Datei
LOCAL_MC_VERSION="0"
LOCAL_LOADER_VERSION="0"
if [ -f "$FABRIC_VERSION_FILE" ]; then
    LOCAL_MC_VERSION=$(yq -r '.minecraft' "$FABRIC_VERSION_FILE" 2>/dev/null)
    LOCAL_LOADER_VERSION=$(yq -r '.loader' "$FABRIC_VERSION_FILE" 2>/dev/null)
fi

echo "Installierte Version: MC ${LOCAL_MC_VERSION:-'Keine'} / Loader ${LOCAL_LOADER_VERSION:-'Keine'}"
echo "Neueste Version:      MC ${MC_VERSION} / Loader ${LOADER_VERSION}"

# Vergleiche Versionen und führe Update durch, wenn nötig
if [[ "$LOCAL_MC_VERSION" != "$MC_VERSION" || "$LOCAL_LOADER_VERSION" != "$LOADER_VERSION" ]]; then
    echo "Update verfügbar! Führe Update durch..."
    create_backup

    # Lade Fabric Installer herunter
    INSTALLER_URL=$(curl -s https://meta.fabricmc.net/v2/versions/installer | jq -r 'map(.url)[0]')
    if [[ -z "$INSTALLER_URL" || "$INSTALLER_URL" == "null" ]]; then
        echo "Fehler: Konnte die URL für den Fabric Installer nicht abrufen."
        exit 1
    fi
    INSTALLER_JAR="fabric-installer.jar"
    echo "Lade Fabric Installer herunter..."
    curl -o "$INSTALLER_JAR" -L "$INSTALLER_URL"

    if [ ! -f "$INSTALLER_JAR" ]; then
        echo "Fehler: Download des Fabric Installers ist fehlgeschlagen."
        exit 1
    fi

    # Führe Installer aus, um den Server zu erstellen/aktualisieren
    echo "Führe Fabric Installer für Minecraft ${MC_VERSION} aus..."
    java -jar "$INSTALLER_JAR" server -mcversion "$MC_VERSION" -downloadMinecraft
    rm "$INSTALLER_JAR" # Lösche den Installer nach Gebrauch

    # Lade die passende Fabric API Mod von Modrinth herunter
    echo "Aktualisiere Fabric API Mod..."
    mkdir -p "$MODS_DIR"
    # Lösche alte Versionen der Fabric API, um Konflikte zu vermeiden
    find "$MODS_DIR" -name "fabric-api-*.jar" -type f -delete
    
    # Mache den API-Aufruf zu Modrinth
    response=$(curl -G -s "https://api.modrinth.com/v2/project/${FABRIC_API_SLUG}/version" \
        --data-urlencode "game_versions=[\"${MC_VERSION}\"]" \
        --data-urlencode "loaders=[\"fabric\"]")

    # Überprüfe die API-Antwort
    if [ -z "$response" ]; then
    echo "Fehler: Keine Antwort von der API erhalten."
    exit 1
    fi

    # Hole die Download-URL für die neueste, kompatible Version
    download_url=$(echo "$response" | jq -r '.[0].files[0].url')

    # Überprüfe, ob die Download-URL erfolgreich extrahiert wurde
    if [ -z "$download_url" ]; then
    echo "Fehler: Keine Download-URL gefunden."
    exit 1
    fi

    # Lade die Datei herunter
    echo "Lade Fabric API von $download_url herunter..."
    curl -L "$download_url" -o "$MODS_DIR/fabric-api.jar"

    echo "Download abgeschlossen und in $MODS_DIR/fabric-api.jar gespeichert."

    # Schreibe die neuen Versionen in die Tracking-Datei
    echo "minecraft: ${MC_VERSION}" > "$FABRIC_VERSION_FILE"
    echo "loader: ${LOADER_VERSION}" >> "$FABRIC_VERSION_FILE"
    echo "Update abgeschlossen."
else
    echo "Server ist bereits aktuell."
    # Führe trotzdem eine Backup-Prüfung durch, falls nach Intervall fällig
    create_backup 
fi

echo ""
echo "Starte Minecraft Fabric Server..."
if [ ! -f "fabric-server-launch.jar" ]; then
    echo "FEHLER: fabric-server-launch.jar nicht gefunden! Der Server kann nicht gestartet werden."
    echo "Führe das Skript erneut aus, um die Installation zu versuchen."
    exit 1
fi
java ${JAVA_ARGS} -jar fabric-server-launch.jar nogui
