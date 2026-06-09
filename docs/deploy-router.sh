#!/bin/sh
# =============================================================================
# deploy-router.sh
# Script de déploiement CLAGE Home Server (CHSD) sur OpenWrt
# Cible : MikroTik RB951Ui-2HnD, Chaos Calmer 15.05.1 (ar71xx/mikrotik)
#
# Usage (sur le routeur en SSH, en root) :
#   sh deploy-router.sh <IP_SERVEUR_HTTP>
#
# Exemple :
#   sh deploy-router.sh 192.168.23.73
#
# Prérequis :
#   - Les archives chsd-deploy.tar.gz, chsd-libs.tar.gz et le fichier
#     iowarrior.ko doivent être servis via HTTP sur IP_SERVEUR_HTTP:8000
#     (ex: python3 -m http.server 8000 dans le dossier du repo)
# =============================================================================

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <IP_SERVEUR_HTTP>"
    echo "Exemple: $0 192.168.23.73"
    exit 1
fi

SERVER_IP="$1"
SERVER_PORT="8000"
BASE_URL="http://${SERVER_IP}:${SERVER_PORT}"
KERNEL_VER="$(uname -r)"

log() {
    echo ">>> $1"
}

# -----------------------------------------------------------------------------
# Étape 1 — Packages OpenWrt
# -----------------------------------------------------------------------------
log "Installation des packages OpenWrt..."
opkg update

opkg install \
    lighttpd \
    lighttpd-mod-proxy \
    lighttpd-mod-cgi \
    lighttpd-mod-webdav \
    lighttpd-mod-alias \
    lighttpd-mod-setenv

opkg install lighttpd-mod-ssl px5g 2>/dev/null || \
    log "lighttpd-mod-ssl non disponible, SSL optionnel ignoré"

opkg install avahi-dbus-daemon dbus libavahi-client
opkg install sqlite3-cli libsqlite3

# Modules kernel USB (absents du firmware mikrotik par défaut)
opkg install kmod-usb-core kmod-usb2 kmod-usb-ohci kmod-usb-uhci kmod-usb-hid

log "Packages installés."

# -----------------------------------------------------------------------------
# Étape 2 — Module iowarrior (dongle IO-Warrior 868 MHz)
# -----------------------------------------------------------------------------
log "Téléchargement du module iowarrior..."
wget "${BASE_URL}/iowarrior.ko" -O /tmp/iowarrior.ko

log "Installation du module iowarrior..."
cp /tmp/iowarrior.ko "/lib/modules/${KERNEL_VER}/iowarrior.ko"
echo iowarrior > /etc/modules.d/70-usb-iowarrior
insmod "/lib/modules/${KERNEL_VER}/iowarrior.ko"

log "Vérification du module iowarrior..."
lsmod | grep iowarrior && log "iowarrior chargé avec succès" || log "ATTENTION: iowarrior non visible dans lsmod"
ls /dev/usb/iowarrior* 2>/dev/null && log "Dongle IO-Warrior détecté" || log "Dongle non encore visible (normal si USB non initialisé)"

# -----------------------------------------------------------------------------
# Étape 3 — Archive firmware CHSD
# -----------------------------------------------------------------------------
log "Téléchargement de l'archive firmware..."
wget "${BASE_URL}/chsd-deploy.tar.gz" -O /tmp/chsd-deploy.tar.gz

log "Extraction de l'archive firmware..."
cd / && tar xzf /tmp/chsd-deploy.tar.gz

log "Application des permissions..."
chmod 755 /usr/sbin/chsd
chmod 755 /usr/sbin/chs-db /usr/sbin/chs-init /usr/sbin/chs-cron
chmod 755 /usr/sbin/chs-wifirestore /usr/sbin/chs-wifisetup
chmod 755 /usr/sbin/chs-wifiscan /usr/sbin/chs-update /usr/sbin/chs-version
chmod 755 /etc/init.d/chsd /etc/init.d/chs-boot /etc/init.d/chs-fixtime
chmod 600 /etc/lighttpd/ssl/server.pem

log "Création des répertoires requis..."
mkdir -p /root/.chsd
chmod 700 /root/.chsd
mkdir -p /var/log/lighttpd
mkdir -p /www/files/config
mkdir -p /www/files/export
mkdir -p /tmp/.chsd/update

# -----------------------------------------------------------------------------
# Étape 4 — Bibliothèques partagées
# -----------------------------------------------------------------------------
log "Téléchargement des bibliothèques partagées..."
wget "${BASE_URL}/chsd-libs.tar.gz" -O /tmp/chsd-libs.tar.gz

log "Extraction des bibliothèques..."
cd / && tar xzf /tmp/chsd-libs.tar.gz

log "Mise à jour du cache du linker..."
ldconfig 2>/dev/null || true

log "Vérification des dépendances de chsd..."
ldd /usr/sbin/chsd 2>/dev/null | grep "not found" && {
    log "ATTENTION: Dépendances manquantes ! Vérifier l'archive chsd-libs.tar.gz"
} || log "Toutes les dépendances résolues"

# -----------------------------------------------------------------------------
# Étape 5 — Configuration lighttpd
# -----------------------------------------------------------------------------
log "Configuration de lighttpd pour CHSD..."
if grep -q 'lighttpd\.conf' /etc/init.d/lighttpd 2>/dev/null; then
    sed -i 's/lighttpd\.conf/lighttpd-chsd.conf/' /etc/init.d/lighttpd
    log "Init script lighttpd patché"
else
    log "Init script lighttpd déjà configuré"
fi

# -----------------------------------------------------------------------------
# Étape 6 — Activation des services
# -----------------------------------------------------------------------------
log "Activation des services au démarrage..."
/etc/init.d/chs-boot enable
/etc/init.d/chs-fixtime enable
/etc/init.d/chsd enable
/etc/init.d/lighttpd enable
/etc/init.d/avahi-daemon enable

# Désactiver uhttpd si présent (CLAGE utilise lighttpd)
if [ -f /etc/init.d/uhttpd ]; then
    /etc/init.d/uhttpd stop 2>/dev/null || true
    /etc/init.d/uhttpd disable 2>/dev/null || true
    log "uhttpd désactivé"
fi

# -----------------------------------------------------------------------------
# Étape 7 — Démarrage des services
# -----------------------------------------------------------------------------
log "Démarrage des services..."
/etc/init.d/chs-boot boot
/etc/init.d/avahi-daemon start 2>/dev/null || true
/etc/init.d/lighttpd start
/etc/init.d/chsd boot

log "Attente du démarrage (5s)..."
sleep 5

# -----------------------------------------------------------------------------
# Étape 8 — Vérification finale
# -----------------------------------------------------------------------------
echo ""
echo "================================================================"
echo " VÉRIFICATION FINALE"
echo "================================================================"

echo ""
echo "--- Processus chsd ---"
ps | grep -v grep | grep chsd || echo "ATTENTION: chsd ne tourne pas"

echo ""
echo "--- Derniers logs CHSD ---"
logread | grep -E 'chsd|chs-' | tail -15

echo ""
echo "--- Test API HTTP (port 8080) ---"
curl -s http://127.0.0.1:8080/server && echo "" || echo "Port 8080 ne répond pas"

echo ""
echo "--- Test lighttpd (port 80) ---"
curl -s -o /dev/null -w "HTTP %{http_code}" http://127.0.0.1/ && echo "" || echo "Port 80 ne répond pas"

echo ""
echo "================================================================"
echo " ID Serveur CHSD : $(uci get chsd.server.id 2>/dev/null || echo 'non configuré')"
echo "================================================================"
echo ""
echo "Déploiement terminé. Consulter les logs ci-dessus pour vérifier."
echo "En cas d'erreur 'USB/SPI: Failed to open device', vérifier :"
echo "  lsmod | grep iowarrior"
echo "  ls /dev/usb/"
echo "  dmesg | tail -30"
