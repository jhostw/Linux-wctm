#!/usr/bin/env bash
#
# Instalación interactiva de Arch Linux
# GRUB + btrfs (@ @home @snapshots @var_cache @var_log) + /efi separado
# Locale: en_US.UTF-8  |  Timezone: America/Lima  |  CPU: AMD (amd-ucode)
#
# Ejecutar desde el ISO live de Arch Linux en modo UEFI.
#
# REANUDACIÓN: el progreso se guarda en /root/.arch-install-state (RAM del ISO).
# Si el script falla y lo vuelves a correr SIN reiniciar, detecta el paso anterior.
# Si reinicias el ISO por completo, el estado se pierde y hay que empezar de cero.
#
set -euo pipefail

# ══════════════════════════════════════════════════════
#  COLORES Y ESTILOS
# ══════════════════════════════════════════════════════
R=$'\033[0m'         # reset
BOLD=$'\033[1m'
DIM=$'\033[2m'
C_CYAN=$'\033[36m'
C_BLUE=$'\033[34m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_WHITE=$'\033[97m'
C_GRAY=$'\033[90m'
BG_BLUE=$'\033[44m'
BG_CYAN=$'\033[46m'

# ══════════════════════════════════════════════════════
#  HELPERS DE IMPRESIÓN
# ══════════════════════════════════════════════════════
info()    { echo -e " ${BOLD}${C_CYAN}::${R} ${BOLD}$*${R}"; }
ok()      { echo -e " ${C_GREEN}✔${R}  $*"; }
warn()    { echo -e " ${C_YELLOW}▲${R}  $*"; }
fail()    { echo -e " ${C_RED}✘${R}  ${BOLD}$*${R}"; exit 1; }
label()   { echo -e " ${C_GRAY}──────────────────────────────────────────────${R}"; }
newline() { echo; }

# Limpia la pantalla y muestra el banner + barra de progreso
screen() {
    local title="${1:-}"
    local step_n="${2:-}"
    local step_total="${3:-}"
    clear
    # El box tiene 47 chars de ancho interior para que las dos líneas queden iguales
    echo -e "${BOLD}${C_CYAN}"
    echo "  ╔═════════════════════════════════════════════╗"
    echo "  ║       Arch Linux Installer  v1.0            ║"
    echo "  ║    btrfs · GRUB · UEFI · AMD · zsh          ║"
    echo "  ╚═════════════════════════════════════════════╝${R}"
    if [[ -n "$title" ]]; then
        echo -e "  ${DIM}${C_GRAY}$(date '+%H:%M:%S')${R}  ${BOLD}${title}${R}"
    fi
    if [[ -n "$step_n" && -n "$step_total" ]]; then
        local bar_width=24
        local filled=$(( step_n * bar_width / step_total ))
        local empty=$(( bar_width - filled ))
        local bar=""
        local i
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty; i++)); do bar+="░"; done
        echo -e "  ${C_GRAY}Paso ${step_n}/${step_total}${R}  ${C_CYAN}${BOLD}${bar}${R}"
    fi
    echo
}

# Prompt estándar con valor por defecto resaltado
ask() {
    # ask "Label" "default_val" VARNAME
    local label_="$1"
    local default_="$2"
    local varname="$3"
    local hint=""
    [[ -n "$default_" ]] && hint=" ${C_GRAY}[Enter = ${default_}]${R}"
    echo -ne " ${BOLD}${label_}${R}${hint}: "
    local val
    read -r val
    printf -v "$varname" '%s' "${val:-$default_}"
}

# Prompt de contraseña (sin eco, confirma)
ask_password() {
    local prompt="$1"
    local varname="$2"
    local p1 p2
    while true; do
        echo -ne " ${BOLD}${prompt}${R}: "
        read -rsp "" p1; echo
        echo -ne " ${C_GRAY}Confirmar ${prompt}${R}: "
        read -rsp "" p2; echo
        if [[ -z "$p1" ]]; then
            warn "La contraseña no puede estar vacía. Intenta de nuevo."
            echo
            continue
        fi
        if [[ "$p1" != "$p2" ]]; then
            warn "Las contraseñas no coinciden. Intenta de nuevo."
            echo
            continue
        fi
        printf -v "$varname" '%s' "$p1"
        ok "Contraseña establecida."
        echo
        break
    done
}

# ══════════════════════════════════════════════════════
#  MENÚ INTERACTIVO CON FLECHAS + NÚMERO
#  Uso: arrow_menu "Título" items_array_name → resultado en ARROW_RESULT
#
#  Controles:
#    ↑ / ↓   — mover selección
#    1-9     — seleccionar directamente por número
#    Enter   — confirmar
# ══════════════════════════════════════════════════════
ARROW_RESULT=0
arrow_menu() {
    local _am_title="$1"
    local -n _am_items="$2"   # nameref al array (bash 4.3+)
    local _am_sel=0
    local _am_count="${#_am_items[@]}"

    tput civis 2>/dev/null || true   # ocultar cursor

    # Dibuja el menú desde la posición guardada con tput sc.
    # Usa printf con ancho fijo para sobreescribir limpiamente líneas anteriores
    # (evita artefactos del color de fondo al cambiar de ítem).
    _am_draw() {
        tput rc 2>/dev/null || true   # restaurar posición guardada
        echo -e " ${BOLD}${_am_title}${R}"
        label
        local _i
        for (( _i=0; _i<_am_count; _i++ )); do
            local _num=$(( _i + 1 ))
            if [[ $_i -eq $_am_sel ]]; then
                # Padding de 70 chars para sobreescribir líneas más largas previas
                printf "  ${BG_CYAN}${C_WHITE}${BOLD} %d ❯ %-65s${R}\n" \
                    "$_num" "${_am_items[$_i]}"
            else
                printf "  ${C_GRAY}  %d   %-65s${R}\n" \
                    "$_num" "${_am_items[$_i]}"
            fi
        done
        echo
    }

    tput sc 2>/dev/null || true   # guardar posición del cursor ANTES de dibujar
    _am_draw

    local _key _esc
    while true; do
        IFS= read -rsn1 _key
        case "$_key" in
            $'\x1b')   # secuencia de escape (flechas)
                IFS= read -rsn1 -t 0.15 _esc || continue
                if [[ "$_esc" == "[" ]]; then
                    IFS= read -rsn1 -t 0.15 _esc || continue
                    case "$_esc" in
                        A)  # flecha arriba
                            if (( _am_sel > 0 )); then
                                _am_sel=$(( _am_sel - 1 ))
                            fi
                            _am_draw
                            ;;
                        B)  # flecha abajo
                            if (( _am_sel < _am_count - 1 )); then
                                _am_sel=$(( _am_sel + 1 ))
                            fi
                            _am_draw
                            ;;
                    esac
                fi
                ;;
            [1-9])   # selección por número (1-indexed)
                local _num_sel=$(( _key - 1 ))
                if (( _num_sel >= 0 && _num_sel < _am_count )); then
                    _am_sel=$_num_sel
                    _am_draw
                fi
                ;;
            "")   # Enter — confirmar
                break
                ;;
        esac
    done

    tput cnorm 2>/dev/null || true   # restaurar cursor visible
    ARROW_RESULT=$_am_sel
}

# ══════════════════════════════════════════════════════
#  ESTADO / REANUDACIÓN
# ══════════════════════════════════════════════════════
STATE_FILE="/root/.arch-install-state"
LAST_STEP=0
RESUMED=0

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
        LAST_STEP="${STEP:-0}"
        if [[ "$LAST_STEP" -gt 0 ]]; then
            screen "Instalación anterior detectada"
            warn "Instalación interrumpida en el paso ${LAST_STEP}/6."
            warn "Disco guardado: ${DISK:-desconocido}"
            newline
            local opts=("Continuar desde donde quedó (paso $((LAST_STEP + 1))/6)" "Borrar todo y empezar de cero")
            arrow_menu "¿Qué deseas hacer?" opts
            if [[ "$ARROW_RESULT" -eq 1 ]]; then
                rm -f "$STATE_FILE"
                LAST_STEP=0
                DISK=""; EFI_PART=""; ROOT_PART=""
                ok "Estado anterior descartado."
                sleep 1
            else
                RESUMED=1
                ok "Reanudando desde el paso $((LAST_STEP + 1))."
                sleep 1
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

# ══════════════════════════════════════════════════════
#  VERIFICACIONES PREVIAS
# ══════════════════════════════════════════════════════
require_root() {
    [[ $EUID -eq 0 ]] || fail "Ejecuta este script como root."
}

check_uefi() {
    screen "Verificaciones del sistema" 1 6
    info "Verificando modo de arranque..."
    if [[ -d /sys/firmware/efi/efivars ]]; then
        ok "UEFI detectado."
    else
        fail "No estás en modo UEFI. Reinicia el ISO en modo UEFI."
    fi

    info "Verificando conexión a internet..."
    if ping -c 1 -W 3 archlinux.org &>/dev/null; then
        ok "Conexión a internet detectada."
    else
        warn "Sin conexión a internet."
        echo
        local opts=("Reintentar (tengo cable/DHCP)" "Abrir iwctl (WiFi)")
        arrow_menu "¿Cómo conectarte?" opts
        if [[ "$ARROW_RESULT" -eq 1 ]]; then
            tput cnorm 2>/dev/null || true
            iwctl
        fi
        if ping -c 1 -W 3 archlinux.org &>/dev/null; then
            ok "Conexión a internet detectada."
        else
            fail "Sigue sin haber internet. Revisa el cable/red y vuelve a correr el script."
        fi
    fi

    info "Sincronizando reloj del sistema..."
    timedatectl set-ntp true
    ok "Reloj sincronizado."
    sleep 0.8
}

# ══════════════════════════════════════════════════════
#  SELECCIÓN DE DISCO
# ══════════════════════════════════════════════════════
select_disk() {
    if [[ -n "${DISK:-}" && "$RESUMED" -eq 1 ]]; then
        screen "Disco" 2 6
        ok "Reutilizando disco de la instalación anterior: ${BOLD}$DISK${R}"
        [[ -b "$DISK" ]] || fail "El disco guardado '$DISK' ya no existe. Empieza de cero."
        sleep 1
        return
    fi

    screen "Selección de disco" 2 6

    # Construir lista de discos (excluye loops y ROM)
    mapfile -t DISK_LIST < <(lsblk -dpno NAME,SIZE,MODEL | grep -v "loop" | grep -v "rom")
    if [[ ${#DISK_LIST[@]} -eq 0 ]]; then
        fail "No se detectaron discos físicos."
    fi

    arrow_menu "Selecciona el disco de instalación (↑↓ para mover, Enter para elegir)" DISK_LIST
    local chosen="${DISK_LIST[$ARROW_RESULT]}"
    DISK="$(echo "$chosen" | awk '{print $1}')"
    [[ -b "$DISK" ]] || fail "El dispositivo '$DISK' no existe."

    if [[ "$DISK" =~ nvme || "$DISK" =~ mmcblk ]]; then
        PART_SUFFIX="p"
    else
        PART_SUFFIX=""
    fi
    EFI_PART="${DISK}${PART_SUFFIX}1"
    ROOT_PART="${DISK}${PART_SUFFIX}2"

    newline
    ok "Disco seleccionado: ${BOLD}$DISK${R}"
    echo -e "  ${C_GRAY}├── EFI  : ${EFI_PART}  (1G, FAT32)${R}"
    echo -e "  ${C_GRAY}└── ROOT : ${ROOT_PART}  (resto, btrfs + 5 subvolúmenes)${R}"
    sleep 1
}

# ══════════════════════════════════════════════════════
#  CONFIGURACIÓN INTERACTIVA
# ══════════════════════════════════════════════════════
BASE_PACKAGES="base linux linux-firmware amd-ucode btrfs-progs grub efibootmgr networkmanager sudo vim nano neovim zsh base-devel"
EXTRA_PACKAGES=""
HOSTNAME=""
USERNAME=""
ROOT_PASSWORD=""
USER_PASSWORD=""
TIMEZONE="America/Lima"
LOCALE="en_US.UTF-8"
KEYMAP="us"

ask_config() {
    # -- Hostname --
    screen "Configuración  ·  Hostname" 3 6
    info "¿Cómo se llamará esta máquina en la red?"
    newline
    while true; do
        ask "Hostname" "archbox" HOSTNAME
        [[ -n "$HOSTNAME" ]] && break
        warn "El hostname no puede estar vacío."
    done

    # -- Usuario --
    screen "Configuración  ·  Usuario" 3 6
    info "Cuenta de usuario principal (se añade al grupo wheel → sudo)."
    newline
    while true; do
        ask "Nombre de usuario" "" USERNAME
        [[ -n "$USERNAME" ]] && break
        warn "El nombre de usuario no puede estar vacío."
    done

    # -- Contraseña root --
    screen "Configuración  ·  Contraseña de root" 3 6
    info "Contraseña para el usuario ${BOLD}root${R}."
    newline
    ask_password "Contraseña de root" ROOT_PASSWORD

    # -- Contraseña usuario --
    screen "Configuración  ·  Contraseña de usuario" 3 6
    info "Contraseña para el usuario ${BOLD}${USERNAME}${R}."
    newline
    ask_password "Contraseña de $USERNAME" USER_PASSWORD

    # -- Timezone --
    screen "Configuración  ·  Zona horaria" 3 6
    info "Timezone del sistema."
    newline
    while true; do
        ask "Timezone" "America/Lima" TIMEZONE
        if [[ -f "/usr/share/zoneinfo/$TIMEZONE" ]]; then
            ok "Timezone válido: $TIMEZONE"
            break
        else
            warn "Timezone '$TIMEZONE' no encontrado. Ej: America/Lima, America/Bogota"
        fi
    done

    # -- Locale --
    screen "Configuración  ·  Locale" 3 6
    info "Idioma del sistema (locale)."
    newline
    ask "Locale" "en_US.UTF-8" LOCALE
    ok "Locale: $LOCALE"

    # -- Paquetes extra --
    screen "Configuración  ·  Paquetes" 3 6
    info "Paquetes base que se instalarán:"
    newline
    echo -e "  ${C_GRAY}$BASE_PACKAGES${R}"
    newline
    info "¿Quieres agregar paquetes extra ahora?"
    echo -e "  ${C_GRAY}Ejemplos: git htop firefox alacritty${R}"
    newline
    ask "Paquetes extra" "(ninguno)" _extra_raw
    if [[ "$_extra_raw" == "(ninguno)" || -z "$_extra_raw" ]]; then
        EXTRA_PACKAGES=""
    else
        EXTRA_PACKAGES="$_extra_raw"
    fi
    sleep 0.5
}

# ══════════════════════════════════════════════════════
#  RESUMEN Y CONFIRMACIÓN
# ══════════════════════════════════════════════════════
show_summary() {
    screen "Resumen de instalación" 4 6

    local destruir
    if [[ "$LAST_STEP" -lt 1 ]]; then
        destruir="${C_RED}${BOLD}SE BORRARÁ TODO${R}"
    else
        destruir="${C_YELLOW}Reutilizando particiones existentes${R}"
    fi

    echo -e "  ${BOLD}${C_CYAN}DISCO${R}"
    echo -e "    Dispositivo  : ${BOLD}$DISK${R}  ($destruir)"
    echo -e "    ${C_GRAY}├── EFI  : $EFI_PART  (1G, FAT32)${R}"
    echo -e "    ${C_GRAY}└── ROOT : $ROOT_PART  (btrfs → @ @home @snapshots @var_cache @var_log)${R}"
    newline
    echo -e "  ${BOLD}${C_CYAN}SISTEMA${R}"
    echo -e "    Hostname     : ${BOLD}$HOSTNAME${R}"
    echo -e "    Usuario      : ${BOLD}$USERNAME${R}  (sudo via wheel, shell: zsh)"
    echo -e "    Timezone     : $TIMEZONE"
    echo -e "    Locale       : $LOCALE"
    echo -e "    Bootloader   : GRUB UEFI  (ESP en /efi)"
    echo -e "    Microcódigo  : amd-ucode (AMD Ryzen)"
    newline
    echo -e "  ${BOLD}${C_CYAN}PAQUETES${R}"
    echo -e "    ${C_GRAY}$BASE_PACKAGES${R}"
    [[ -n "$EXTRA_PACKAGES" ]] && echo -e "    ${C_YELLOW}Extra: $EXTRA_PACKAGES${R}"
    newline
    label
    newline

    if [[ "$LAST_STEP" -lt 1 ]]; then
        warn "Esta acción ${BOLD}borrará de forma permanente${R} todo el contenido de ${BOLD}$DISK${R}."
        newline
    fi

    local opts=("Sí, comenzar instalación" "No, cancelar y salir")
    arrow_menu "¿Confirmas que todo está correcto?" opts
    [[ "$ARROW_RESULT" -eq 0 ]] || fail "Instalación cancelada por el usuario."
}

# ══════════════════════════════════════════════════════
#  EJECUCIÓN: PARTICIONADO
# ══════════════════════════════════════════════════════
do_partition() {
    if [[ "$LAST_STEP" -ge 1 ]]; then
        ok "[1/6] Particionado ya completado, se omite."
        return
    fi
    screen "Particionado del disco" 1 6
    info "Borrando tabla de particiones..."
    sgdisk --zap-all "$DISK"
    wipefs -a "$DISK"     # limpia firmas de FS que sgdisk a veces deja

    info "Creando particiones..."
    sgdisk -n1:0:+1G  -t1:ef00 -c1:"EFI System"       "$DISK"
    sgdisk -n2:0:0    -t2:8300 -c2:"Linux filesystem"  "$DISK"
    partprobe "$DISK"
    sleep 2
    ok "Particiones creadas:"
    lsblk "$DISK"
    save_state 1
    sleep 1
}

# ══════════════════════════════════════════════════════
#  EJECUCIÓN: FORMATEO Y SUBVOLÚMENES
# ══════════════════════════════════════════════════════
do_format_and_subvolumes() {
    if [[ "$LAST_STEP" -ge 2 ]]; then
        ok "[2/6] Formateo ya completado, remontando..."
        remount_existing
        return
    fi
    screen "Formateo y subvolúmenes btrfs" 2 6

    info "Formateando EFI ($EFI_PART) → FAT32..."
    mkfs.fat -F32 -n EFI "$EFI_PART"

    info "Formateando ROOT ($ROOT_PART) → btrfs..."
    mkfs.btrfs -f -L arch "$ROOT_PART"

    info "Creando subvolúmenes..."
    mount "$ROOT_PART" /mnt
    for sv in @ @home @snapshots @var_cache @var_log; do
        btrfs subvolume create "/mnt/$sv"
        ok "  subvolumen creado: $sv"
    done
    umount /mnt

    mount_all
    ok "Sistema de archivos listo:"
    findmnt /mnt -R
    save_state 2
    sleep 1
}

mount_all() {
    info "Montando subvolúmenes en /mnt..."
    local opts="noatime,compress=zstd,ssd,space_cache=v2"
    mount -o "${opts},subvol=@"          "$ROOT_PART" /mnt
    mkdir -p /mnt/{home,.snapshots,var/cache,var/log,efi}
    mount -o "${opts},subvol=@home"      "$ROOT_PART" /mnt/home
    mount -o "${opts},subvol=@snapshots" "$ROOT_PART" /mnt/.snapshots
    mount -o "${opts},subvol=@var_cache" "$ROOT_PART" /mnt/var/cache
    mount -o "${opts},subvol=@var_log"   "$ROOT_PART" /mnt/var/log
    mount "$EFI_PART" /mnt/efi
}

remount_existing() {
    if findmnt /mnt &>/dev/null; then
        ok "/mnt ya montado."
        return
    fi
    mount_all
    ok "Subvolúmenes remontados."
}

# ══════════════════════════════════════════════════════
#  EJECUCIÓN: PACSTRAP
# ══════════════════════════════════════════════════════
do_pacstrap() {
    remount_existing
    if [[ "$LAST_STEP" -ge 3 ]]; then
        ok "[3/6] pacstrap ya completado, se omite."
        return
    fi
    screen "Instalando sistema base" 3 6
    info "Ejecutando pacstrap (puede tomar varios minutos según tu conexión)..."
    newline
    # SC2086: expansión intencional de $EXTRA_PACKAGES sin comillas para palabras múltiples
    # shellcheck disable=SC2086
    pacstrap -K /mnt $BASE_PACKAGES $EXTRA_PACKAGES
    ok "Sistema base instalado."
    save_state 3
    sleep 1
}

# ══════════════════════════════════════════════════════
#  EJECUCIÓN: FSTAB
# ══════════════════════════════════════════════════════
do_genfstab() {
    remount_existing
    if [[ "$LAST_STEP" -ge 4 ]]; then
        ok "[4/6] fstab ya generado, se omite."
        return
    fi
    screen "Generando fstab" 4 6
    info "Generando /etc/fstab con UUIDs..."
    genfstab -U /mnt >> /mnt/etc/fstab
    ok "fstab generado:"
    newline
    cat /mnt/etc/fstab
    save_state 4
    sleep 1
}

# ══════════════════════════════════════════════════════
#  EJECUCIÓN: CONFIGURACIÓN EN CHROOT
# ══════════════════════════════════════════════════════
do_chroot_config() {
    remount_existing
    if [[ "$LAST_STEP" -ge 5 ]]; then
        ok "[5/6] Chroot ya configurado, se omite."
        return
    fi
    screen "Configurando sistema (chroot)" 5 6

    cat > /mnt/root/chroot-setup.sh <<CHROOT_EOF
#!/usr/bin/env bash
set -euo pipefail

echo "==> Timezone..."
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

echo "==> Locale..."
sed -i "s/^#${LOCALE} UTF-8/${LOCALE} UTF-8/" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf

echo "==> Keymap..."
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

echo "==> Hostname y hosts..."
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS_EOF

echo "==> Contraseña de root..."
echo "root:${ROOT_PASSWORD}" | chpasswd

echo "==> Creando usuario ${USERNAME}..."
useradd -m -G wheel -s /usr/bin/zsh "${USERNAME}"
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

echo "==> Habilitando sudo para wheel..."
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "==> Habilitando NetworkManager..."
systemctl enable NetworkManager

echo "==> Instalando GRUB (UEFI, /efi)..."
# amd-ucode ya está instalado por pacstrap; grub-mkconfig lo detecta solo.
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=wctm
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Chroot listo."
CHROOT_EOF

    chmod +x /mnt/root/chroot-setup.sh
    arch-chroot /mnt /root/chroot-setup.sh
    rm /mnt/root/chroot-setup.sh
    ok "Sistema configurado: timezone, locale, hostname, usuario, GRUB."
    save_state 5
    sleep 1
}

# ══════════════════════════════════════════════════════
#  CIERRE
# ══════════════════════════════════════════════════════
do_finish() {
    screen "¡Instalación completa!" 6 6

    # ── Copiar postinstall.sh al home del usuario ─────
    # Busca postinstall.sh en el mismo directorio que este script.
    # Si lo encuentra, lo copia al home del nuevo usuario y le da permisos
    # para que esté listo para ejecutar después del primer boot.
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local postinstall_src="${script_dir}/postinstall.sh"
    local user_home="/mnt/home/${USERNAME}"

    if [[ -f "$postinstall_src" ]]; then
        info "Copiando postinstall.sh al home de ${USERNAME}..."
        cp "$postinstall_src" "${user_home}/postinstall.sh"
        chmod +x "${user_home}/postinstall.sh"
        arch-chroot /mnt chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}/postinstall.sh"
        ok "postinstall.sh listo en ~/postinstall.sh"
    else
        warn "No se encontró postinstall.sh junto a install.sh."
        warn "Cópialo manualmente al home de ${USERNAME} después del boot."
    fi

    info "Desmontando particiones..."
    umount -R /mnt
    rm -f "$STATE_FILE"

    newline
    echo -e "  ${BOLD}${C_GREEN}✔  Arch Linux instalado exitosamente.${R}"
    newline
    label

    newline
    echo -e "  ${BOLD}${C_CYAN}SISTEMA${R}"
    echo -e "  ${C_GRAY}  ├─ Hostname    ${R}${BOLD}${HOSTNAME}${R}"
    echo -e "  ${C_GRAY}  ├─ Usuario     ${R}${BOLD}${USERNAME}${R}${C_GRAY}  (sudo · zsh)${R}"
    echo -e "  ${C_GRAY}  ├─ Disco       ${R}${BOLD}${DISK}${R}"
    echo -e "  ${C_GRAY}  ├─ Bootloader  ${R}GRUB UEFI${C_GRAY}  (ESP en /efi)${R}"
    echo -e "  ${C_GRAY}  └─ Filesystem  ${R}btrfs${C_GRAY}  · @ @home @snapshots @var_cache @var_log${R}"

    newline
    echo -e "  ${BOLD}${C_CYAN}PRÓXIMO PASO${R}"
    echo -e "  ${C_GRAY}  1. Quita el USB / ISO${R}"
    echo -e "  ${C_GRAY}  2. Reinicia e inicia sesión como ${R}${BOLD}${USERNAME}${R}"
    echo -e "  ${C_GRAY}  3. Ejecuta ${R}${BOLD}./postinstall.sh${R}${C_GRAY} para instalar Hyprland y el entorno${R}"
    newline
    label
    newline

    local opts=("Reiniciar ahora (quita el USB antes)" "Salir sin reiniciar")
    arrow_menu "¿Qué deseas hacer?" opts
    if [[ "$ARROW_RESULT" -eq 0 ]]; then
        ok "Reiniciando en 3 segundos..."
        sleep 3
        reboot
    else
        warn "Reinicia cuando estés listo con: ${BOLD}reboot${R}"
    fi
}

# ══════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════
main() {
    require_root
    load_state
    check_uefi
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
