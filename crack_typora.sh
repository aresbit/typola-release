#!/bin/bash
# Crack Typora on Ubuntu based on juejin article
# Backup original files
BACKUP_DIR="$HOME/typora_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Backing up original files to $BACKUP_DIR"
sudo cp -n /usr/share/typora/resources/page-dist/static/js/LicenseIndex*.js "$BACKUP_DIR/" 2>/dev/null
sudo cp -n /usr/share/typora/resources/page-dist/license.html "$BACKUP_DIR/" 2>/dev/null

echo "Modifying JavaScript license check..."
JS_FILE="/usr/share/typora/resources/page-dist/static/js/LicenseIndex*.js"
# Use find to get exact file path
JS_PATH=$(sudo find /usr/share/typora/resources/page-dist/static/js -name "LicenseIndex*.js" -type f | head -1)
if [ -z "$JS_PATH" ]; then
    echo "Error: LicenseIndex.js not found"
    exit 1
fi

echo "Editing $JS_PATH"
# Replace e.hasActivated="true"==something with e.hasActivated="true"=="true"
sudo sed -i 's/\(e\.hasActivated="true"==\)[^"]*/\1"true"/g' "$JS_PATH"
if [ $? -eq 0 ]; then
    echo "JavaScript modification done"
else
    echo "JavaScript modification failed"
fi

echo "Modifying license.html..."
LICENSE_FILE="/usr/share/typora/resources/page-dist/license.html"
# Insert script before </body>
sudo sed -i 's|</body>|<script>setTimeout(function () {window.close()}, 10);</script></body>|' "$LICENSE_FILE"
if [ $? -eq 0 ]; then
    echo "license.html modification done"
else
    echo "license.html modification failed"
fi

echo "Crack completed. Please restart Typora."