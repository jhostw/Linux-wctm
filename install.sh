#!/usr/bin/env bash
#
# Instalación interactiva de Arch Linux
# GRUB + btrfs (@ @home @snapshots @var_cache @var_log) + /efi separado
# Locale: en_US.UTF-8  |  Timezone: America/Lima  |  CPU: AMD (amd-ucode)
#
# Correr esto DESDE el ISO live de Arch Linux (booteado en modo UEFI).
#
# NOTA SOBRE REANUDACIÓN: el progreso se guarda en /root/.arch-install-state,
# que vive en la RAM del ISO live. Si el script falla o lo cierras y lo vuelves
# a correr SIN reiniciar la laptop, detecta en qué paso te quedaste y te deja
# continuar. Si reinicias la laptop por completo durante la instalación, ese
# archivo de estado se pierde (porque el ISO live es efímero) y hay que
# empezar de cero.
#
set -euo pipefail

# ---------- Colores / helpers ----------
C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[32m'; C_RED='\033[31m'; C_YELLOW='\033[33m'; C_BLUE='\033[34m'

info()  { echo -e "${C_BLUE}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
ok()    { echo -e "${C_GREEN}✔${C_RESET} $*"; }
warn()  { echo -e "${C_YELLOW}⚠${C_RESET} $*"; }
fail()  { echo -e "${C_RED}✘ $*${C_RESET}"; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || fail "Este script debe correr como root (en el ISO live ya lo eres por defecto)."
}

# ---------- Estado / reanudación ----------
# Pasos en orden: 1=PARTITION 2=FORMAT 3=PACSTRAP 4=FSTAB 5=CHROOT 6=DONE
STATE_FILE="/root/.arch-install-state"
LAST_STEP=0
RESUMED=0

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$STATE_FILE"
        LAST_STEP="${STEP:-0}"
        if [[ "$LAST_STEP" -gt 0 ]]; then
            warn "Se detectó una instalación previa interrumpida (último paso completado: $LAST_STEP/6)."
            warn "Disco guardado: ${DISK:-desconocido}"
            read -rp "¿Continuar desde donde quedó? [S/n] (n = borrar todo y empezar de cero): " resume
            if [[ "${resume,,}" == "n" ]]; then
                rm -f "$STATE_FILE"
                LAST_STEP=0
                DISK=""; EFI_PART=""; ROOT_PART=""
                ok "Estado anterior descartado. Empezamos de cero."
            else
                RESUMED=1
                ok "Reanudando desde el paso $((LAST_STEP + 1))."
            fi
        fi
    fi
}

save_state() {
    local step="$1"
    cat > "$STATE_FILE" <<EOF
STEP=${step}
DISK=${DISK}
EFI_PART=${EFI_PART}
ROOT_PART=${ROOT_PART}
EOF
}

# ---------- 1. Verificaciones previas ----------
check_uefi() {
    info "Verificando modo de arranque..."
    if [[ -d /sys/firmware/efi/efivars ]]; then
        ok "Sistema booteado en modo UEFI."
    else
        fail "No estás en modo UEFI. Este script asume UEFI + GRUB. Reinicia booteando el ISO en modo UEFI."
    fi
}

check_internet() {
    info "Verificando conexión a internet..."
    if ping -c 1 -W 3 archlinux.org &>/dev/null; then
        ok "Conexión a internet detectada."
        return
    fi
    warn "No se detectó conexión a internet."
    echo "Si usas cable, revisa que esté bien conectado; a veces solo falta esperar al DHCP."
    read -rp "Presiona ENTER para reintentar, o escribe 'wifi' para configurar WiFi con iwctl: " resp
    if [[ "${resp,,}" == "wifi" ]]; then
        iwctl
    fi
    if ping -c 1 -W 3 archlinux.org &>/dev/null; then
        ok "Conexión a internet detectada."
    else
        fail "Sigue sin haber internet. Revisa el cable/red y vuelve a correr el script."
    fi
}

sync_clock() {
    info "Sincronizando reloj del sistema..."
    timedatectl set-ntp true
    ok "Reloj sincronizado."
}

# ---------- 2. Selección de disco ----------
select_disk() {
    if [[ -n "${DISK:-}" && "$RESUMED" -eq 1 ]]; then
        ok "Usando disco de la instalación anterior: $DISK"
        [[ -b "$DISK" ]] || fail "El disco guardado '$DISK' ya no existe. Empieza de cero."
        return
    fi
    info "Discos disponibles:"
    lsblk -dpno NAME,SIZE,MODEL | grep -v "loop"
    echo
    read -rp "Escribe el disco a usar (ej. /dev/nvme0n1): " DISK
    [[ -b "$DISK" ]] || fail "El dispositivo '$DISK' no existe."

    # Detectar sufijo de partición: nvme/mmcblk usan 'p1','p2'; sdX usa '1','2'
    if [[ "$DISK" =~ nvme || "$DISK" =~ mmcblk ]]; then
        PART_SUFFIX="p"
    else
        PART_SUFFIX=""
    fi
    EFI_PART="${DISK}${PART_SUFFIX}1"
    ROOT_PART="${DISK}${PART_SUFFIX}2"

    warn "Se usará: $DISK"
    warn "  Partición EFI : $EFI_PART (1G)"
    warn "  Partición raíz: $ROOT_PART (resto del disco, btrfs)"
}

# ---------- 3. Preguntas interactivas ----------
BASE_PACKAGES="base linux linux-firmware amd-ucode btrfs-progs grub efibootmgr networkmanager sudo vim nano neovim zsh base-devel"

ask_config() {
    read -rp "Hostname (nombre de la máquina): " HOSTNAME
    [[ -n "$HOSTNAME" ]] || fail "El hostname no puede estar vacío."

    read -rp "Nombre de usuario: " USERNAME
    [[ -n "$USERNAME" ]] || fail "El usuario no puede estar vacío."

    ask_password() {
        local prompt="$1"
        local p1 p2
        while true; do
            read -rsp "$prompt: " p1; echo
            read -rsp "Confirma $prompt: " p2; echo
            if [[ -z "$p1" ]]; then
                warn "La contraseña no puede estar vacía. Intenta de nuevo."
                continue
            fi
            if [[ "$p1" != "$p2" ]]; then
                warn "Las contraseñas no coinciden. Intenta de nuevo."
                continue
            fi
            printf -v "$2" '%s' "$p1"
            break
        done
    }

    ask_password "Contraseña de root" ROOT_PASSWORD
    ask_password "Contraseña de usuario '$USERNAME'" USER_PASSWORD

    read -rp "Timezone [America/Lima]: " TIMEZONE
    TIMEZONE="${TIMEZONE:-America/Lima}"
    [[ -f "/usr/share/zoneinfo/$TIMEZONE" ]] || fail "Timezone inválido: $TIMEZONE"

    read -rp "Locale [en_US.UTF-8]: " LOCALE
    LOCALE="${LOCALE:-en_US.UTF-8}"

    KEYMAP="us"

    echo
    echo "Paquetes base que se instalarán: $BASE_PACKAGES"
    read -rp "¿Paquetes extra a instalar? (separados por espacio, ENTER para ninguno): " EXTRA_PACKAGES
    EXTRA_PACKAGES="${EXTRA_PACKAGES:-}"
}

# ---------- 4. Resumen y confirmación ----------
show_summary() {
    echo
    echo -e "${C_BOLD}====== RESUMEN DE INSTALACIÓN ======${C_RESET}"
    echo "Disco a usar          : $DISK  $( [[ "$LAST_STEP" -lt 1 ]] && echo '(TODO el contenido se borrará)' || echo '(reutilizando particiones existentes)' )"
    echo "  -> EFI  : $EFI_PART   1G    FAT32"
    echo "  -> ROOT : $ROOT_PART  resto btrfs (@ @home @snapshots @var_cache @var_log)"
    echo "Hostname               : $HOSTNAME"
    echo "Usuario                : $USERNAME (con sudo, shell por defecto: zsh)"
    echo "Timezone               : $TIMEZONE"
    echo "Locale                 : $LOCALE"
    echo "Teclado                : $KEYMAP"
    echo "Swap                   : Ninguno"
    echo "Bootloader             : GRUB (UEFI), ESP montado en /efi"
    echo "Microcódigo CPU        : amd-ucode (AMD Ryzen)"
    echo "Paquetes base          : $BASE_PACKAGES"
    [[ -n "$EXTRA_PACKAGES" ]] && echo "Paquetes extra         : $EXTRA_PACKAGES"
    echo -e "${C_BOLD}=====================================${C_RESET}"
    echo

    if [[ "$LAST_STEP" -lt 1 ]]; then
        warn "Esto BORRARÁ TODO el contenido de $DISK de forma irreversible."
    else
        warn "Se reutilizarán las particiones ya creadas en una corrida anterior. No se volverá a borrar el disco."
    fi
    read -rp "Escribe CONFIRMAR (en mayúsculas) para continuar: " CONFIRM
    [[ "$CONFIRM" == "CONFIRMAR" ]] || fail "Cancelado por el usuario."
}

# ---------- 5. Particionado ----------
do_partition() {
    if [[ "$LAST_STEP" -ge 1 ]]; then
        ok "[Paso 1/6] Particionado ya completado anteriormente, se omite."
        return
    fi
    info "[Paso 1/6] Borrando tabla de particiones de $DISK..."
    sgdisk --zap-all "$DISK"
    # Limpieza extra de firmas de filesystem que sgdisk a veces no toca
    wipefs -a "$DISK"

    info "Creando particiones..."
    sgdisk -n1:0:+1G   -t1:ef00 -c1:"EFI System" "$DISK"
    sgdisk -n2:0:0     -t2:8300 -c2:"Linux filesystem" "$DISK"

    partprobe "$DISK"
    sleep 2
    ok "Particiones creadas."
    lsblk "$DISK"
    save_state 1
}

# ---------- 6. Formateo y subvolúmenes btrfs ----------
do_format_and_subvolumes() {
    if [[ "$LAST_STEP" -ge 2 ]]; then
        ok "[Paso 2/6] Formateo ya completado anteriormente, remontando subvolúmenes existentes..."
        remount_existing
        return
    fi
    info "[Paso 2/6] Formateando partición EFI ($EFI_PART) como FAT32..."
    mkfs.fat -F32 -n EFI "$EFI_PART"

    info "Formateando partición raíz ($ROOT_PART) como btrfs..."
    mkfs.btrfs -f -L arch "$ROOT_PART"

    info "Creando subvolúmenes..."
    mount "$ROOT_PART" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@snapshots
    btrfs subvolume create /mnt/@var_cache
    btrfs subvolume create /mnt/@var_log
    umount /mnt
    ok "Subvolúmenes creados: @ @home @snapshots @var_cache @var_log"

    mount_all
    ok "Todo montado en /mnt"
    findmnt /mnt -R
    save_state 2
}

mount_all() {
    info "Montando subvolúmenes..."
    local opts="noatime,compress=zstd,ssd,space_cache=v2"
    mount -o "${opts},subvol=@" "$ROOT_PART" /mnt
    mkdir -p /mnt/{home,.snapshots,var/cache,var/log,efi}
    mount -o "${opts},subvol=@home" "$ROOT_PART" /mnt/home
    mount -o "${opts},subvol=@snapshots" "$ROOT_PART" /mnt/.snapshots
    mount -o "${opts},subvol=@var_cache" "$ROOT_PART" /mnt/var/cache
    mount -o "${opts},subvol=@var_log" "$ROOT_PART" /mnt/var/log
    mount "$EFI_PART" /mnt/efi
}

# Usado cuando reanudamos después del paso 2: si /mnt no está montado, lo remonta
# usando los subvolúmenes YA EXISTENTES (no los vuelve a crear).
remount_existing() {
    if findmnt /mnt &>/dev/null; then
        ok "/mnt ya está montado, se mantiene como está."
        return
    fi
    mount_all
    ok "Subvolúmenes existentes remontados en /mnt."
    findmnt /mnt -R
}

# ---------- 7. pacstrap ----------
do_pacstrap() {
    remount_existing
    if [[ "$LAST_STEP" -ge 3 ]]; then
        ok "[Paso 3/6] pacstrap ya completado anteriormente, se omite."
        return
    fi
    info "[Paso 3/6] Instalando sistema base con pacstrap (esto toma un rato)..."
    # pacstrap/pacman son seguros de re-ejecutar: si se cae a mitad de descarga,
    # al volver a correr este paso retoma donde quedó sin reinstalar lo ya hecho.
    # shellcheck disable=SC2086
    pacstrap -K /mnt $BASE_PACKAGES $EXTRA_PACKAGES
    ok "Sistema base instalado."
    save_state 3
}

# ---------- 8. fstab ----------
do_genfstab() {
    remount_existing
    if [[ "$LAST_STEP" -ge 4 ]]; then
        ok "[Paso 4/6] fstab ya generado anteriormente, se omite."
        return
    fi
    info "[Paso 4/6] Generando fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
    ok "fstab generado."
    cat /mnt/etc/fstab
    save_state 4
}

# ---------- 9. Configuración en chroot ----------
do_chroot_config() {
    remount_existing
    if [[ "$LAST_STEP" -ge 5 ]]; then
        ok "[Paso 5/6] Configuración de chroot ya completada anteriormente, se omite."
        return
    fi
    info "[Paso 5/6] Configurando sistema dentro del chroot..."

    cat > /mnt/root/chroot-setup.sh <<CHROOT_EOF
#!/usr/bin/env bash
set -euo pipefail

# Timezone
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

# Locale
sed -i "s/^#${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf

# Keymap
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# Hostname
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS_EOF

# Root password
echo "root:${ROOT_PASSWORD}" | chpasswd

# Usuario, con zsh como shell por defecto
useradd -m -G wheel -s /usr/bin/zsh "${USERNAME}"
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# NetworkManager
systemctl enable NetworkManager

# GRUB (UEFI, ESP en /efi). amd-ucode ya quedó instalado por pacstrap,
# grub-mkconfig detecta /boot/amd-ucode.img automáticamente.
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT_EOF

    chmod +x /mnt/root/chroot-setup.sh
    arch-chroot /mnt /root/chroot-setup.sh
    rm /mnt/root/chroot-setup.sh
    ok "Configuración de chroot completada (timezone, locale, hostname, usuario, zsh, GRUB)."
    save_state 5
}

# ---------- 10. Cierre ----------
do_finish() {
    info "[Paso 6/6] Desmontando particiones..."
    umount -R /mnt
    save_state 6
    rm -f "$STATE_FILE"
    ok "Instalación completa."
    echo
    read -rp "¿Reiniciar ahora? [s/N]: " reboot_now
    if [[ "${reboot_now,,}" == "s" ]]; then
        reboot
    else
        warn "Recuerda quitar el medio de instalación y reiniciar manualmente con: reboot"
    fi
}

# ---------- MAIN ----------
main() {
    require_root
    load_state
    check_uefi
    check_internet
    sync_clock
    select_disk
    ask_config
    show_summary
    do_partition
    do_format_and_subvolumes
    do_pacstrap
    do_genfstab
    do_chroot_config
    do_finish
}

main "$@"
