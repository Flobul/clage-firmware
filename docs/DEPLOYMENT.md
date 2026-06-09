# Déploiement CLAGE Home Server (CHSD) sur OpenWrt

## Contexte

Ce dépôt contient le firmware et la configuration du **CLAGE Home Server (CHSD)**, un daemon qui gère la communication entre un réseau local et un chauffe-eau CLAGE via un dongle USB 868 MHz (émetteur STM32 avec interface IO-Warrior).

### Matériel cible

| Composant | Valeur |
|-----------|--------|
| Routeur | MikroTik RB951Ui-2HnD |
| Firmware OpenWrt | Chaos Calmer 15.05.1 (`ar71xx/mikrotik`) |
| Dongle USB | Émetteur 868 MHz à base de STM32, interface IO-Warrior |
| Kernel | 3.18.23 |

### Architecture

```
[Chauffe-eau CLAGE]
        |  (868 MHz RF)
[Dongle USB IO-Warrior STM32]
        |  (USB)
[Routeur MikroTik RB951Ui-2HnD]
   ├── chsd (daemon)          ← port interne 8080
   ├── lighttpd (proxy HTTP)  ← port 80/443
   └── avahi-daemon (mDNS)
```

---

## Prérequis

### Problème firmware mikrotik : USB non supporté

Le firmware `ar71xx/mikrotik` de Chaos Calmer **ne compile pas** le module kernel `iowarrior` nécessaire pour le dongle IO-Warrior. Il faut le compiler manuellement depuis le SDK OpenWrt puis le déployer.

Le firmware `ar71xx/generic` inclut USB nativement, mais la cible `mikrotik` est utilisée ici.

---

## Étape 1 — Compiler le module iowarrior (sur un PC Linux x86_64)

Voir le script `build-iowarrior.sh` pour une version automatisée. Les étapes manuelles :

### 1.1 Installer les dépendances

```bash
apt-get install -y \
  build-essential gawk git subversion unzip wget curl file time \
  python2.7 bzip2 libncurses5-dev zlib1g-dev libssl-dev rsync
```

### 1.2 Créer un utilisateur de build dédié

```bash
useradd -m build
# Travailler ensuite en tant que 'build' pour éviter les problèmes de droits
su - build
```

### 1.3 Cloner le dépôt OpenWrt Chaos Calmer

```bash
cd /home/build
git clone https://github.com/openwrt/chaos_calmer.git openwrt-cc
cd openwrt-cc
```

### 1.4 Configurer la cible et le package iowarrior

```bash
# Configurer la cible ar71xx/mikrotik et activer iowarrior
cat > .config <<'EOF'
CONFIG_TARGET_ar71xx=y
CONFIG_TARGET_ar71xx_mikrotik=y
CONFIG_PACKAGE_kmod-usb-iowarrior=m
EOF

make defconfig
```

> **Note :** Si le package `kmod-usb-iowarrior` n'existe pas dans la version du SDK, créer le fichier de définition manuellement (voir 1.5).

### 1.5 (Si nécessaire) Créer la définition du package iowarrior

```bash
mkdir -p package/kernel/linux/modules/

cat > package/kernel/linux/modules/usb.mk <<'EOF'
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
EOF
```

### 1.6 Compiler le module kernel

```bash
# Compiler uniquement les modules kernel (plus rapide que make world)
make package/kernel/linux/compile V=s
```

La compilation prend environ 15-30 minutes selon la machine.

### 1.7 Récupérer le module compilé

```bash
# Méthode 1 : via le SDK après compilation
find build_dir -name "iowarrior.ko" 2>/dev/null

# Méthode 2 : compilation directe du module (plus rapide si le kernel est déjà compilé)
export PATH="/home/build/openwrt-cc/staging_dir/toolchain-mips_34kc_gcc-4.8-linaro_uClibc-0.9.33.2/bin:$PATH"

KDIR="$(find build_dir -type d -path '*linux-ar71xx_mikrotik/linux-3.18.23' | head -1)"
echo "Kernel dir: $KDIR"

# S'assurer que CONFIG_USB_IOWARRIOR=m est dans la config kernel
grep CONFIG_USB_IOWARRIOR "$KDIR/.config" || echo 'CONFIG_USB_IOWARRIOR=m' >> "$KDIR/.config"

# Compiler uniquement le driver iowarrior
make -C "$KDIR" \
  ARCH=mips \
  CROSS_COMPILE=mips-openwrt-linux-uclibc- \
  M=drivers/usb/misc \
  modules V=1

# Trouver le .ko
find "$KDIR/drivers/usb/misc" -name "iowarrior.ko"
```

### 1.8 Transférer le module sur le routeur

```bash
# Depuis le PC, copier vers le routeur
scp /chemin/vers/iowarrior.ko root@192.168.204.204:/tmp/
```

---

## Étape 2 — Préparer les archives de déploiement (sur le PC)

### 2.1 Archive des fichiers firmware

```bash
cd /chemin/vers/clage-firmware

tar czf /tmp/chsd-deploy.tar.gz \
  usr/sbin/chsd \
  usr/sbin/chs-db \
  usr/sbin/chs-init \
  usr/sbin/chs-cron \
  usr/sbin/chs-wifirestore \
  usr/sbin/chs-wifisetup \
  usr/sbin/chs-wifiscan \
  usr/sbin/chs-update \
  usr/sbin/chs-version \
  etc/init.d/chsd \
  etc/init.d/chs-boot \
  etc/init.d/chs-fixtime \
  etc/config/chsd \
  etc/lighttpd/lighttpd-chsd.conf \
  etc/lighttpd/ssl/server.pem \
  etc/avahi/avahi-daemon.conf \
  etc/avahi/services/clage-hs.service \
  etc/hotplug.d/iface/50-chs-wifidn \
  etc/hotplug.d/net/10-ar922x-led-fix \
  etc/crontabs/root \
  root/.chsd/ \
  www/files/ \
  www/index.html
```

### 2.2 Archive des bibliothèques partagées

Le binaire `chsd` dépend de bibliothèques absentes du firmware `mikrotik` de base :

```bash
cd /chemin/vers/clage-firmware

tar czf /tmp/chsd-libs.tar.gz \
  usr/lib/libmicrohttpd.so \
  usr/lib/libmicrohttpd.so.10 \
  usr/lib/libmicrohttpd.so.10.14.0 \
  usr/lib/libevent-2.0.so.5 \
  usr/lib/libevent-2.0.so.5.1.9 \
  usr/lib/libevent_core-2.0.so.5 \
  usr/lib/libevent_core-2.0.so.5.1.9 \
  usr/lib/libevent_extra-2.0.so.5 \
  usr/lib/libevent_extra-2.0.so.5.1.9 \
  usr/lib/libevent_openssl-2.0.so.5 \
  usr/lib/libevent_openssl-2.0.so.5.1.9 \
  usr/lib/libevent_pthreads-2.0.so.5 \
  usr/lib/libevent_pthreads-2.0.so.5.1.9 \
  usr/lib/libiowkit.so \
  usr/lib/libiowkit.so.1 \
  usr/lib/libiowkit.so.1.0.5 \
  usr/lib/libmodbus.so \
  usr/lib/libmodbus.so.5 \
  usr/lib/libmodbus.so.5.0.5 \
  usr/lib/libstdc++.so.6 \
  usr/lib/libstdc++.so.6.0.19 \
  lib/libudev.so \
  lib/libudev.so.0 \
  lib/libudev.so.0.12.0
```

### 2.3 Servir les fichiers via HTTP (simple)

```bash
cd /tmp
python3 -m http.server 8000
# Les fichiers sont accessibles sur http://<IP_PC>:8000/
```

---

## Étape 3 — Installer les packages OpenWrt (sur le routeur)

```sh
opkg update

# Packages système requis
opkg install \
  lighttpd \
  lighttpd-mod-proxy \
  lighttpd-mod-cgi \
  lighttpd-mod-webdav \
  lighttpd-mod-alias \
  lighttpd-mod-setenv

# SSL pour lighttpd
opkg install lighttpd-mod-ssl px5g 2>/dev/null || true

# Avahi (mDNS) + D-Bus
opkg install avahi-dbus-daemon dbus libavahi-client

# SQLite3
opkg install sqlite3-cli libsqlite3

# Modules kernel USB (absents du firmware mikrotik par défaut)
opkg install kmod-usb-core kmod-usb2 kmod-usb-ohci kmod-usb-uhci kmod-usb-hid
```

> **Note sur les erreurs attendues :**
> - `lighttpd` : avertissement `Undefined config variable: var.home_dir` → ignorable, on utilisera `lighttpd-chsd.conf`
> - `avahi` : conflit de conffile → résolu à l'étape 5
> - `lighttpd-mod-openssl` introuvable → utiliser `lighttpd-mod-ssl`
> - `netdiscover` introuvable → non requis par CHSD

---

## Étape 4 — Installer le module iowarrior (sur le routeur)

```sh
# Télécharger le module compilé à l'étape 1
wget http://<IP_PC>:8000/iowarrior.ko -O /tmp/iowarrior.ko

# Installer le module
cp /tmp/iowarrior.ko /lib/modules/$(uname -r)/iowarrior.ko

# Enregistrer pour chargement automatique au boot
echo iowarrior > /etc/modules.d/70-usb-iowarrior

# Charger immédiatement
insmod /lib/modules/$(uname -r)/iowarrior.ko

# Vérifier
dmesg | tail -20
lsmod | grep iowarrior
ls /dev/usb/iowarrior* 2>/dev/null
```

Si le dongle est reconnu, `dmesg` affiche quelque chose comme :
```
iowarrior: USB IOWarrior driver v0.4.8 (08/04/2004)
usb 1-1: new full-speed USB device number 2 using ohci-hcd
usb 1-1: New USB device found, idVendor=07c0, idProduct=...
iowarrior: IOWarrior ... at usb-..., minor 0
```

---

## Étape 5 — Déployer les fichiers firmware (sur le routeur)

```sh
# Télécharger et extraire l'archive firmware
wget http://<IP_PC>:8000/chsd-deploy.tar.gz -O /tmp/chsd-deploy.tar.gz
cd / && tar xzf /tmp/chsd-deploy.tar.gz

# Télécharger et extraire les bibliothèques
wget http://<IP_PC>:8000/chsd-libs.tar.gz -O /tmp/chsd-libs.tar.gz
cd / && tar xzf /tmp/chsd-libs.tar.gz

# Permissions des binaires et scripts
chmod 755 /usr/sbin/chsd
chmod 755 /usr/sbin/chs-db /usr/sbin/chs-init /usr/sbin/chs-cron
chmod 755 /usr/sbin/chs-wifirestore /usr/sbin/chs-wifisetup
chmod 755 /usr/sbin/chs-wifiscan /usr/sbin/chs-update /usr/sbin/chs-version
chmod 755 /etc/init.d/chsd /etc/init.d/chs-boot /etc/init.d/chs-fixtime
chmod 600 /etc/lighttpd/ssl/server.pem

# Dossiers requis par chsd et lighttpd
mkdir -p /root/.chsd
chmod 700 /root/.chsd
mkdir -p /var/log/lighttpd
mkdir -p /www/files/config
mkdir -p /www/files/export
mkdir -p /tmp/.chsd/update

# Mettre à jour le cache du linker dynamique
ldconfig 2>/dev/null || true

# Vérifier les dépendances de chsd (tout doit être résolu)
ldd /usr/sbin/chsd
```

La sortie de `ldd` doit montrer toutes les libs résolues (pas de `not found`).

---

## Étape 6 — Configurer lighttpd (sur le routeur)

Le firmware Chaos Calmer install lighttpd avec `lighttpd.conf` par défaut. Il faut le faire pointer vers `lighttpd-chsd.conf` :

```sh
# Patcher l'init script lighttpd
if grep -q 'lighttpd\.conf' /etc/init.d/lighttpd; then
    sed -i 's/lighttpd\.conf/lighttpd-chsd.conf/' /etc/init.d/lighttpd
    echo "Init script patché"
fi

# Vérifier
grep lighttpd /etc/init.d/lighttpd | grep -i configfile
```

---

## Étape 7 — Activer les services (sur le routeur)

```sh
# Activer au démarrage
/etc/init.d/chs-boot enable
/etc/init.d/chs-fixtime enable
/etc/init.d/chsd enable
/etc/init.d/lighttpd enable
/etc/init.d/avahi-daemon enable

# Désactiver uhttpd (CLAGE utilise lighttpd à la place)
if [ -f /etc/init.d/uhttpd ]; then
    /etc/init.d/uhttpd stop 2>/dev/null
    /etc/init.d/uhttpd disable 2>/dev/null
    echo "uhttpd désactivé"
fi
```

---

## Étape 8 — Démarrer les services (sur le routeur)

```sh
# Démarrer dans l'ordre
/etc/init.d/chs-boot boot
/etc/init.d/avahi-daemon start
/etc/init.d/lighttpd start
/etc/init.d/chsd boot

# Attendre quelques secondes
sleep 5
```

---

## Étape 9 — Vérification

```sh
# Le daemon chsd doit apparaître (pas seulement le wrapper shell)
ps | grep -v grep | grep chsd

# Logs du daemon
logread | grep -E 'chsd|chs-' | tail -20

# Le daemon doit démarrer et trouver le dongle USB
# Succès : "Starting daemon ... " sans "Failed to open device"

# Tester l'API HTTP interne
curl -s http://127.0.0.1:8080/server

# Tester via lighttpd (proxy)
curl -s http://127.0.0.1/

# Port 443 (HTTPS) si SSL configuré
curl -sk https://127.0.0.1/
```

### Logs attendus en cas de succès

```
daemon.notice chsd[XXXX]: CLAGE Home Server v1.3.1
daemon.notice chsd[XXXX]: Starting daemon (sid=CCFFE0FF36FF, port=8080, ...)...
daemon.notice chsd[XXXX]: USB/SPI: Device opened successfully
```

---

## Référence ID Serveur

L'ID serveur CHSD (`chsd.server.id`) est dérivé de l'adresse MAC de l'interface ethernet. Il est stocké dans `/etc/config/chsd` :

```sh
uci get chsd.server.id   # ex: CCFFE0FF36FF
```

Les 4 derniers octets (`36FF` dans l'exemple) sont utilisés pour le SSID WiFi (`CLAGE-HS-36FF`) et le hostname (`chs-36D2`).

Pour forcer un ID spécifique (ex. lors d'une remise à zéro) :
```sh
uci set chsd.server.id='CCFFE0FF36FF'
uci commit chsd
```

---

## Dépannage

### `USB/SPI: Failed to open device!`
- Vérifier que le module `iowarrior` est chargé : `lsmod | grep iowarrior`
- Vérifier que le dongle est reconnu : `ls /dev/usb/`
- Recharger le module : `rmmod iowarrior; insmod /lib/modules/$(uname -r)/iowarrior.ko`
- Vérifier dmesg : `dmesg | tail -30`

### `/sys/bus/usb/` absent
- Le module USB core n'est pas chargé
- Installer : `opkg install kmod-usb-core kmod-usb2 kmod-usb-ohci`
- Puis recharger : `modprobe usbcore`

### `can't load library 'libXXX.so'`
- La lib est manquante dans `/usr/lib/` ou `/lib/`
- Vérifier avec `ldd /usr/sbin/chsd`
- Redéployer l'archive `chsd-libs.tar.gz`

### Erreur 500 sur `http://routeur/`
- `chsd` ne tourne pas (lighttpd proxifie vers 8080 qui ne répond pas)
- Vérifier : `ps | grep chsd` et `curl -s http://127.0.0.1:8080/server`

### Symboles USB manquants dans dmesg (`Unknown symbol usb_hcd_*`)
- Le module ehci/ohci a été chargé avant usbcore
- Solution : `rmmod ehci-hcd ohci-hcd; modprobe usbcore; modprobe ehci-hcd; modprobe ohci-hcd`
