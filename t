#!/bin/bash
# Skript zur Einrichtung von Nextcloud auf Ubuntu 20.04,
# wobei ein bereits vorhandener ZFS-Pool (nas_pool) genutzt wird.
# Es wird kein neuer ZFS-Pool angelegt!

# Sicherstellen, dass das Skript als root ausgeführt wird
if [ "$(id -u)" -ne 0 ]; then
  echo "Bitte als root oder mit sudo ausführen!"
  exit 1
fi

set -e

echo "System aktualisieren..."
apt update && apt upgrade -y

echo "Notwendige Pakete installieren..."
apt install -y apache2 mariadb-server php libapache2-mod-php \
    php-mysql php-gd php-json php-curl php-mbstring php-intl php-xml php-zip unzip ufw

# MariaDB-Setup: Datenbank und Benutzer für Nextcloud
# Zugangsdaten: admin / 123123
NEXTCLOUD_DB="nextcloud"
NEXTCLOUD_DB_USER="admin"
NEXTCLOUD_DB_PASS="123123"

echo "Datenbank für Nextcloud einrichten..."
mysql -e "CREATE DATABASE IF NOT EXISTS ${NEXTCLOUD_DB};"
mysql -e "DROP USER IF EXISTS '${NEXTCLOUD_DB_USER}'@'localhost';"
mysql -e "CREATE USER '${NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON ${NEXTCLOUD_DB}.* TO '${NEXTCLOUD_DB_USER}'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Nutzung des vorhandenen ZFS-Pools (z. B. "Nas")
POOL_NAME="nas_pool"
MOUNTPOINT=$(zfs get -H -o value mountpoint $POOL_NAME || true)

if [ -z "$MOUNTPOINT" ]; then
  echo "Fehler: ZFS-Pool ${POOL_NAME} wurde nicht gefunden oder besitzt keinen Mountpoint!"
  exit 1
fi

echo "Verwende vorhandenen ZFS-Pool '${POOL_NAME}' mit Mountpoint '${MOUNTPOINT}'"

# Nextcloud-Datenverzeichnis im ZFS-Pool erstellen
NEXTCLOUD_DATA_DIR="${MOUNTPOINT}/nextcloud_data"
mkdir -p "$NEXTCLOUD_DATA_DIR"
chown -R www-data:www-data "$NEXTCLOUD_DATA_DIR"

# Nextcloud herunterladen und entpacken (Version anpassen falls nötig)
NEXTCLOUD_VERSION="25.0.0"
echo "Lade Nextcloud Version ${NEXTCLOUD_VERSION} herunter..."
wget -O /tmp/nextcloud.zip "https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.zip"
echo "Entpacke Nextcloud..."
unzip -q /tmp/nextcloud.zip -d /var/www/
chown -R www-data:www-data /var/www/nextcloud

# Apache-Konfiguration für Nextcloud erstellen – Port 8081
echo "Erstelle Apache-Konfiguration für Nextcloud (Port 8081)..."
cat > /etc/apache2/sites-available/nextcloud.conf <<EOF
<VirtualHost *:8081>
    ServerAdmin admin@deinedomain.de
    DocumentRoot /var/www/nextcloud
    ServerName nextcloud.deinedomain.de

    <Directory /var/www/nextcloud/>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>
EOF

# Apache so konfigurieren, dass er auf Port 8081 lauscht
sed -i 's/^Listen 80/Listen 8081/' /etc/apache2/ports.conf

a2ensite nextcloud.conf
a2enmod rewrite headers env dir mime
systemctl reload apache2

# UFW: Port 8081 freischalten
echo "Öffne Port 8081/tcp in der Firewall..."
ufw allow 8081/tcp
ufw reload

# Nextcloud-Installation per occ-Befehl (Admin: admin / 123123, Datenverzeichnis: $NEXTCLOUD_DATA_DIR)
echo "Starte die Nextcloud-Installation (CLI)..."
sudo -u www-data php /var/www/nextcloud/occ maintenance:install \
    --database "mysql" \
    --database-name "${NEXTCLOUD_DB}" \
    --database-user "${NEXTCLOUD_DB_USER}" \
    --database-pass "${NEXTCLOUD_DB_PASS}" \
    --admin-user "${NEXTCLOUD_DB_USER}" \
    --admin-pass "${NEXTCLOUD_DB_PASS}" \
    --data-dir "$NEXTCLOUD_DATA_DIR"

echo "Fertig! Nextcloud ist nun erreichbar unter http://<IP oder Domain>:8081"
