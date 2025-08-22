# MC Pro Start - Minecraft Server Start- und Verwaltungsskript

Ein umfassendes Bash-Skript zur Automatisierung von Betrieb und Wartung eines PaperMC Minecraft-Servers. Es bietet Funktionen für automatische Updates, ein flexibles Backup-System und einen einfachen Rollback-Mechanismus.

## ✨ Funktionen

- **🚀 Automatische Server-Updates**: Prüft vor jedem Start die neueste PaperMC-Version (einschließlich Build-Nummer).
- **🔒 Sichere und verifizierte Downloads**: Lädt neue Server-JARs herunter und verifiziert deren Integrität mithilfe von SHA256-Hashes, um Beschädigungen zu verhindern.
- **🗄️ Flexibles Backup-System**:
- Erstellt automatisch ein Backup vor einem Server-Update.
- Erstellt Backups in einem konfigurierbaren Intervall (z. B. alle 24 Stunden).
- Bereinigt alte Backups automatisch anhand einer maximalen Anzahl und einer Aufbewahrungsdauer.
- Vollständig konfigurierbar über eine einfache „backup.yml“-Datei.
- **⏪ Rollback-Funktionalität**: Stellen Sie den Server mit einem einzigen Befehl einfach auf den Zustand des letzten Backups zurück.
- **✅ Abhängigkeitsprüfung**: Stellt sicher, dass alle erforderlichen Befehlszeilentools vor der Ausführung installiert sind.

## 📋 Voraussetzungen

Dieses Skript ist für Linux-basierte Betriebssysteme konzipiert und erfordert die Installation der folgenden Befehlszeilentools:

- `curl`: Zum Senden von API-Anfragen und Herunterladen von Dateien.
- `jq`: Zum Parsen von JSON-Antworten der PaperMC-API.
- `yq`: Zum Parsen der Konfigurationsdatei `backup.yml`.
- `zip`: Zum Erstellen von Backups.
- `sha256sum`: Zum Überprüfen der Dateiintegrität.
- `date` & `find`: Standard-Linux-Dienstprogramme für Zeit- und Dateiverwaltung.

Sie können diese Tools auf den meisten Systemen mit Ihrem Paketmanager installieren.

**Unter Debian/Ubuntu:**
```bash
sudo apt-get update && sudo apt-get install curl jq yq zip
```

**Unter CentOS/RHEL:**
```bash
sudo yum install curl jq yq zip
```

## ⚙️ Konfiguration

### 1. `start.sh`

Die grundlegenden Konfigurationsvariablen befinden sich oben im `start.sh`-Skript. Hier können Sie Ihre Java-Argumente anpassen.

```bash
# Java-Argumente für den Serverstart
JAVA_ARGS="-Xms4G -Xmx4G ..."
```

### 2. `backup.yml`

Erstellen Sie eine Datei namens `backup.yml` im selben Verzeichnis wie das Skript zur Konfiguration des Backup-Systems.

**Beispiel `backup.yml`:**
```yaml
# Maximale Anzahl der aufzubewahrenden Backups.
Max. Backups: 10

# Intervall für Backups. Verwenden Sie 'h' für Stunden und 'd' für Tage.
# Beispiel: "24h" für täglich, "7d" für wöchentlich. Setzen Sie "0", um Intervall-Backups zu deaktivieren.
Backup-Intervall: "24h"

# Aufbewahrungsdauer von Backups. Ältere Backups werden gelöscht.
# Beispiel: „30d“ für 30 Tage Aufbewahrung der Backups. „0“ deaktiviert die Aufbewahrungsrichtlinie.
Backup-Aufbewahrung: „30d“

# Verzeichnis für die Backups.
Backup-Verzeichnis: „./backups“

# Liste der einzelnen Dateien, die in das Backup aufgenommen werden sollen.
Dateien:
- „server.properties“
- „eula.txt“
- „ops.json“
- „whitelist.json“

# Liste der gesamten Ordner, die in das Backup aufgenommen werden sollen.
Ordner:
- "world"
- "world_nether"
- "world_the_end"
- "plugins"
```

## 🚀 Verwendung

Machen Sie zunächst das Skript ausführbar:
```bash
chmod +x start.sh
```

### Server starten

So starten Sie den Server (einschließlich der Update- und Backup-Prüfung):
```bash
./start.sh
```

### Backup manuell erstellen

So starten Sie den Backup-Prozess, ohne den Server zu starten:
```bash
./start.sh backup
```

### Auf das letzte Backup zurücksetzen

So stellen Sie die Serverdateien und -ordner aus dem letzten Backup wieder her:
**Warnung**: Dadurch werden die aktuellen Serverdateien und -ordner aus Ihrer `backup.yml` gelöscht, bevor Sie aus dem Backup wiederherstellen.

```bash
./start.sh rollback
```

### Eula Check

Bei jedem Start prüft das Skript, ob eine eula.txt vorhanden ist. Ist dies nicht der Fall, fragt das Skript, ob die EULA akzeptiert wird oder nicht.
Wird die EULA akzeptiert, generiert das Skript eine eula.txt mit dem Wert eula=true. Andernfalls bricht es den Vorgang ab.


## 📄 Lizenz

Dieses Projekt ist unter der MIT-Lizenz lizenziert. Weitere Informationen finden Sie in der Lizenzdatei.
