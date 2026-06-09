#!/bin/bash
# =============================================================================
# build-iowarrior.sh
# Compilation du module kernel iowarrior pour OpenWrt Chaos Calmer 15.05.1
# Cible : ar71xx/mikrotik (MikroTik RB951Ui-2HnD), kernel 3.18.23
#
# Usage (en root) :
#   bash build-iowarrior.sh
#
# Résultat : /tmp/iowarrior.ko (à transférer sur le routeur)
# =============================================================================

set -e

OPENWRT_REPO="https://github.com/openwrt/chaos_calmer.git"
BUILD_USER="build"
BUILD_DIR="/home/${BUILD_USER}/openwrt-cc"
OUTPUT="/tmp/iowarrior.ko"

# -----------------------------------------------------------------------------
# 1. Dépendances système
# -----------------------------------------------------------------------------
echo ">>> Installation des dépendances..."
apt-get install -y \
    build-essential gawk git subversion unzip wget curl file time \
    python2.7 bzip2 libncurses5-dev zlib1g-dev libssl-dev rsync

# -----------------------------------------------------------------------------
# 2. Utilisateur de build dédié (les outils OpenWrt refusent de compiler en root)
# -----------------------------------------------------------------------------
if ! id "${BUILD_USER}" &>/dev/null; then
    echo ">>> Création de l'utilisateur ${BUILD_USER}..."
    useradd -m "${BUILD_USER}"
fi

# -----------------------------------------------------------------------------
# 3. Clone du dépôt OpenWrt Chaos Calmer
# -----------------------------------------------------------------------------
if [ -d "${BUILD_DIR}" ]; then
    echo ">>> Dépôt déjà présent dans ${BUILD_DIR}, skip clone."
else
    echo ">>> Clone du dépôt OpenWrt Chaos Calmer..."
    sudo -u "${BUILD_USER}" git clone "${OPENWRT_REPO}" "${BUILD_DIR}"
fi

# -----------------------------------------------------------------------------
# 4. Définition du package kmod-usb-iowarrior
# -----------------------------------------------------------------------------
echo ">>> Création de la définition du package kmod-usb-iowarrior..."
sudo -u "${BUILD_USER}" mkdir -p "${BUILD_DIR}/package/kernel/linux/modules/"

sudo -u "${BUILD_USER}" tee "${BUILD_DIR}/package/kernel/linux/modules/usb.mk" > /dev/null <<'MAKEFILE'
define KernelPackage/usb-iowarrior
  SUBMENU:=$(USB_MENU)
  TITLE:=Code Mercenaries IO-Warrior USB support
  DEPENDS:=+kmod-usb-core
  KCONFIG:=CONFIG_USB_IOWARRIOR
  FILES:=$(LINUX_DIR)/drivers/usb/misc/iowarrior.ko
  AUTOLOAD:=$(call AutoLoad,70,iowarrior)
endef
define KernelPackage/usb-iowarrior/description
 Kernel support for Code Mercenaries IO-Warrior USB devices.
endef
$(eval $(call KernelPackage,usb-iowarrior))
MAKEFILE

# -----------------------------------------------------------------------------
# 5. Configuration OpenWrt
# -----------------------------------------------------------------------------
echo ">>> Configuration de la cible ar71xx/mikrotik..."
sudo -u "${BUILD_USER}" tee "${BUILD_DIR}/.config" > /dev/null <<'CONFIG'
CONFIG_TARGET_ar71xx=y
CONFIG_TARGET_ar71xx_mikrotik=y
CONFIG_PACKAGE_kmod-usb-iowarrior=m
CONFIG

sudo -u "${BUILD_USER}" bash -c "cd '${BUILD_DIR}' && make defconfig"

# -----------------------------------------------------------------------------
# 6. Compilation des modules kernel
# -----------------------------------------------------------------------------
echo ">>> Compilation des modules kernel (peut prendre 15-30 min)..."
sudo -u "${BUILD_USER}" bash -c "cd '${BUILD_DIR}' && make package/kernel/linux/compile V=s"

# -----------------------------------------------------------------------------
# 7. Récupération du .ko compilé
# -----------------------------------------------------------------------------
echo ">>> Recherche du module compilé..."
KO_PATH=$(find "${BUILD_DIR}/build_dir" -name "iowarrior.ko" 2>/dev/null | head -1)

if [ -z "${KO_PATH}" ]; then
    # Tentative de compilation directe du module seul
    echo ">>> Module non trouvé via package, tentative de compilation directe..."
    TOOLCHAIN_BIN=$(find "${BUILD_DIR}/staging_dir" -name "mips-openwrt-linux-uclibc-gcc" 2>/dev/null | head -1)
    TOOLCHAIN_BIN=$(dirname "${TOOLCHAIN_BIN}")
    KDIR=$(find "${BUILD_DIR}/build_dir" -type d -name "linux-3.18.23" -path "*ar71xx_mikrotik*" 2>/dev/null | head -1)

    if [ -z "${KDIR}" ]; then
        echo "ERREUR: Répertoire kernel introuvable. Lancer d'abord 'make package/kernel/linux/compile'."
        exit 1
    fi

    export PATH="${TOOLCHAIN_BIN}:${PATH}"
    grep -q CONFIG_USB_IOWARRIOR "${KDIR}/.config" || echo 'CONFIG_USB_IOWARRIOR=m' >> "${KDIR}/.config"

    make -C "${KDIR}" \
        ARCH=mips \
        CROSS_COMPILE=mips-openwrt-linux-uclibc- \
        M=drivers/usb/misc \
        modules V=1

    KO_PATH=$(find "${KDIR}/drivers/usb/misc" -name "iowarrior.ko" 2>/dev/null | head -1)
fi

if [ -z "${KO_PATH}" ]; then
    echo "ERREUR: Impossible de trouver iowarrior.ko après compilation."
    exit 1
fi

cp "${KO_PATH}" "${OUTPUT}"
echo ""
echo "================================================================"
echo "Module compilé avec succès !"
echo "Fichier : ${OUTPUT}"
echo ""
echo "Transférer sur le routeur :"
echo "  scp ${OUTPUT} root@192.168.204.204:/tmp/"
echo "================================================================"
