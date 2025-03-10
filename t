#!/bin/bash

# Stoppe das Skript bei Fehlern
set -e

echo "==== System-Updates ===="
apt update && apt upgrade -y

echo "==== ZFS-Installation ===="
apt install -y zfsutils-linux
modprobe zfs

echo "==== Alle Partitionen auf /dev/sda löschen ===="
if [ ! -b /dev/sda ]; then
    echo "Fehler: /dev/sda nicht gefunden!"
    exit 1
fi

if zpool list | grep -q nas_pool; then
    echo "Vorhandenen ZFS-Pool 'nas_pool' zerstören..."
    zpool destroy nas_pool
fi

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

echo "==== Installation abgeschlossen! ===="
echo "OpenMediaVault ist jetzt erreichbar unter: http://$(hostname -I | awk '{print $1'}):8081"
