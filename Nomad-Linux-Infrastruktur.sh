#!/bin/bash

# Gemeinsame Schritte für alle Maschinen
install_common_dependencies() {
  echo "\n=== Update und Installation grundlegender Pakete ==="
  sudo apt-get update && sudo apt-get install -y wget gpg coreutils

  echo "\n=== Hinzufügen von HashiCorp GPG-Schlüssel und Repository ==="
  wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

  echo "\n=== Update der Paketquellen und Installation von Nomad ==="
  sudo apt-get update && sudo apt-get install -y nomad

  echo "\n=== Überprüfen der Nomad-Installation ==="
  nomad -v
}

setup_host() {
  echo "\n=== Konfiguration des Hosts ==="
  sudo nomad agent -dev \
    -bind 0.0.0.0 \
    -network-interface='{{ GetDefaultInterfaces | attr "name" }}' &

  export NOMAD_ADDR=http://localhost:4646

  echo "\n=== Nomad Host ist gestartet. Status der Knoten: ==="
  sleep 5
  nomad node status

  echo "\n=== Zugriff auf die Nomad-Web-UI ==="
  echo "Öffnen Sie die folgende URL in Ihrem Browser:"
  echo "http://$(hostname -I | awk '{print $1}'):4646"
}

setup_client() {
  echo "\n=== Konfiguration des Clients ==="
  read -p "Bitte IP-Adresse des Servers eingeben: " server_ip
  sudo nomad agent -client -servers=$server_ip -data-dir=/var/nomad &

  echo "\n=== Nomad Client ist gestartet. ==="
}

install_docker() {
  echo "\n=== Installation von Docker ==="
  sudo apt-get install -y docker.io
  sudo systemctl start docker
  sudo systemctl enable docker

  echo "\n=== Überprüfung der Docker-Installation ==="
  docker --version
}

main_menu() {
  echo "\nWas möchten Sie einrichten?"
  echo "1. Host"
  echo "2. Client"
  echo "3. Docker installieren"
  echo "4. Beenden"
  read -p "Bitte Option wählen [1-4]: " choice

  case $choice in
    1)
      install_common_dependencies
      setup_host
      ;;
    2)
      install_common_dependencies
      setup_client
      ;;
    3)
      install_docker
      ;;
    4)
      echo "Beenden."
      exit 0
      ;;
    *)
      echo "Ungültige Auswahl, bitte erneut versuchen."
      main_menu
      ;;
  esac
}

main_menu
