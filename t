#!/bin/bash

# Stoppe das Skript bei Fehlern
set -e

echo "==== System-Updates ===="
apt update && apt upgrade -y

echo "==== Überprüfe ZFS und installiere es, falls notwendig ===="
# Stelle sicher, dass ZFS-Pakete installiert sind
if ! command -v zfs &> /dev/null; then
    echo "ZFS ist nicht installiert. Installiere ZFS..."
    
    # Benötigte Repositories hinzufügen
    sudo apt install -y software-properties-common
    sudo add-apt-repository ppa:zfs-native/stable
    sudo apt update
    
    # ZFS installieren
    sudo apt install -y zfsutils-linux
    sudo modprobe zfs
fi

# Bestätige, dass ZFS erfolgreich installiert wurde
if ! command -v zfs &> /dev/null; then
    echo "Fehler: ZFS konnte nicht installiert werden!"
    exit 1
fi

echo "ZFS wurde erfolgreich installiert und geladen."

echo "==== Alle Partitionen auf /dev/sda löschen ===="
if [ ! -b /dev/sda ]; then
    echo "Fehler: /dev/sda nicht gefunden!"
    exit 1
fi

# Wenn ein ZFS-Pool existiert, diesen zerstören
if zpool list | grep -q nas_pool; then
    echo "Vorhandenen ZFS-Pool 'nas_pool' zerstören..."
    zpool destroy nas_pool
fi

# Schalte Swap aus und mounte alle Partitionen ab
swapoff -a
umount -f /dev/sda* || true
wipefs -a /dev/sda
sgdisk --zap-all /dev/sda
partprobe /dev/sda

echo "==== ZFS-Pool 'nas_pool' auf /dev/sda erstellen ===="
zpool create -f -o ashift=12 nas_pool /dev/sda
zfs set compression=lz4 nas_pool
zfs set atime=off nas_pool
zfs set mountpoint=/nas nas_pool

echo "==== OpenMediaVault installieren ===="
wget -O - https://github.com/OpenMediaVault-Plugin-Developers/installScript/raw/master/install | sudo bash

echo "==== OMV Port auf 8081 ändern ===="
omv-env set OMV_WEBGUI_PORT 8081
omv-salt stage run prepare
omv-salt deploy run nginx
omv-salt deploy run php-fpm
omv-salt deploy run systemd

echo "==== Samba & NFS installieren ===="
apt install -y samba nfs-kernel-server

echo "==== Benutzer & Rechte setzen ===="
useradd -m -s /bin/bash nasuser
passwd nasuser

echo "==== Nextcloud installieren ===="
apt install -y apache2 mariadb-server libapache2-mod-php php php-mysql php-gd php-json php-curl php-mbstring php-intl php-imagick php-xml php-zip unzip

echo "==== Nextcloud Datenbank anlegen ===="
mysql -u root -e "CREATE DATABASE nextcloud;"
mysql -u root -e "CREATE USER 'nextcloud'@'localhost' IDENTIFIED BY 'nextcloudpass';"
mysql -u root -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';"
mysql -u root -e "FLUSH PRIVILEGES;"

echo "==== Nextcloud herunterladen ===="
wget https://download.nextcloud.com/server/releases/latest.zip
unzip latest.zip -d /var/www/
mv /var/www/nextcloud /var/www/html/nextcloud
chown -R www-data:www-data /var/www/html/nextcloud
chmod -R 755 /var/www/html/nextcloud

echo "==== Nextcloud mit ZFS-Speicher verbinden ===="
mkdir -p /nas/nextcloud
chown -R www-data:www-data /nas/nextcloud
ln -s /nas/nextcloud /var/www/html/nextcloud/data

echo "==== Apache konfigurieren ===="
cat > /etc/apache2/sites-available/nextcloud.conf <<EOF
<VirtualHost *:8082>
    ServerAdmin admin@localhost
    DocumentRoot /var/www/html/nextcloud
    <Directory /var/www/html/nextcloud/>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

a2ensite nextcloud.conf
a2enmod rewrite headers env dir mime
systemctl restart apache2

echo "==== Nextcloud einrichten ===="
sudo -u www-data php /var/www/html/nextcloud/occ maintenance:install --database "mysql" --database-name "nextcloud" --database-user "nextcloud" --database-pass "nextcloudpass" --admin-user "admin" --admin-pass "adminpass"

echo "==== Installation abgeschlossen! ===="
echo "OMV ist unter: http://$(hostname -I | awk '{print $1'}):8081"
echo "Nextcloud ist unter: http://$(hostname -I | awk '{print $1'}):8082"
