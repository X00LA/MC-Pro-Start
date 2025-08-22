# MC Pro Start - Minecraft Server Start & Management Script

A comprehensive bash script to automate the operation and maintenance of a PaperMC Minecraft server. It includes features for automatic updates, a flexible backup system, and a simple rollback mechanism.

## ✨ Features

-   **🚀 Automatic Server Updates**: Checks for the latest PaperMC version (including build number) before every start.
-   **🔒 Secure & Verified Downloads**: Downloads new server JARs and verifies their integrity using SHA256 hashes to prevent corruption.
-   **🗄️ Flexible Backup System**:
    -   Automatically creates a backup before performing a server update.
    -   Creates backups at a configurable interval (e.g., every 24 hours).
    -   Automatically prunes old backups based on a maximum count and a retention period.
    -   Fully configurable via a simple `backup.yml` file.
-   **⏪ Rollback Functionality**: Easily restore the server to the state of the last created backup with a single command.
-   **✅ Dependency Check**: Ensures all required command-line tools are installed before execution.

## 📋 Prerequisites

This script is designed for a Linux-based operating system and requires the following command-line tools to be installed:

-   `curl`: For making API requests and downloading files.
-   `jq`: For parsing JSON responses from the PaperMC API.
-   `yq`: For parsing the `backup.yml` configuration file.
-   `zip`: For creating backups.
-   `sha256sum`: For verifying file integrity.
-   `date` & `find`: Standard Linux utilities for time and file management.

You can install them on most systems with your package manager.

**On Debian/Ubuntu:**
```bash
sudo apt-get update && sudo apt-get install curl jq yq zip
```

**On CentOS/RHEL:**
```bash
sudo yum install curl jq yq zip
```

## ⚙️ Configuration

### 1. `start.sh`

Basic configuration variables are located at the top of the `start.sh` script. You can adjust your Java arguments here.

```bash
# Java arguments for the server start
JAVA_ARGS="-Xms4G -Xmx4G ..."
```

### 2. `backup.yml`

Create a file named `backup.yml` in the same directory as the script to configure the backup system.

**Example `backup.yml`:**
```yaml
# The maximum number of backups to keep.
Max backups: 10

# How often a backup should be created. Use 'h' for hours and 'd' for days.
# Example: "24h" for daily, "7d" for weekly. Set to "0" to disable interval backups.
Backup interval: "24h"

# How long to keep backups. Older backups will be deleted.
# Example: "30d" to keep backups for 30 days. Set to "0" to disable retention policy.
Backup retention: "30d"

# The directory where backups will be stored.
Backup directory: "./backups"

# A list of individual files to include in the backup.
Files:
  - "server.properties"
  - "eula.txt"
  - "ops.json"
  - "whitelist.json"

# A list of entire folders to include in the backup.
Folders:
  - "world"
  - "world_nether"
  - "world_the_end"
  - "plugins"
```

## 🚀 Usage

First, make the script executable:
```bash
chmod +x start.sh
```

### Start the Server

To start the server (which includes the update and backup checks):
```bash
./start.sh
```

### Create a Backup Manually

To trigger the backup process without starting the server:
```bash
./start.sh backup
```

### Rollback to the Last Backup

To restore the server files and folders from the most recent backup:
**Warning**: This will delete the current server files and folders listed in your `backup.yml` before restoring from the backup.

```bash
./start.sh rollback
```

### Eula Check

At every start the script checks if a eula.txt is present. If is not, the script asks if the eula is accepted or not.
If the eula gets accepted the script generates a eula.txt with eula=true in it and if not it cancels the process.

## 📄 License

This project is licensed under the MIT License. See the LICENSE file for details.
