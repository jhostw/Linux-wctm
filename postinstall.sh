#!/usr/bin/env bash
#
# Post-instalación interactiva — Arch Linux
# Hyprland · Kitty · Pipewire · SDDM · LazyVim · AUR helper
#
# Ejecutar después del primer boot, como tu usuario normal (NO como root).
#   chmod +x postinstall.sh && ./postinstall.sh
#
set -euo pipefail

# ══════════════════════════════════════════════════════
#  COLORES Y ESTILOS
# ══════════════════════════════════════════════════════
R=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
C_CYAN=$'\033[36m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_WHITE=$'\033[97m'
C_GRAY=$'\033[90m'
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

screen() {
    local title="${1:-}"
    local step_n="${2:-}"
    local step_total="${3:-}"
    clear
    echo -e "${BOLD}${C_CYAN}"
    echo "  ╔═════════════════════════════════════════════╗"
    echo "  ║     Arch Linux Post-Install  v1.0           ║"
    echo "  ║    Hyprland · Kitty · SDDM · LazyVim        ║"
    echo "  ╚═════════════════════════════════════════════╝${R}"
    if [[ -n "$title" ]]; then
        echo -e "  ${DIM}${C_GRAY}$(date '+%H:%M:%S')${R}  ${BOLD}${title}${R}"
    fi
    if [[ -n "$step_n" && -n "$step_total" ]]; then
        local bar_width=24
        local filled=$(( step_n * bar_width / step_total ))
        local empty=$(( bar_width - filled ))
        local bar="" i
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty; i++)); do bar+="░"; done
        echo -e "  ${C_GRAY}Paso ${step_n}/${step_total}${R}  ${C_CYAN}${BOLD}${bar}${R}"
    fi
    echo
}

# ══════════════════════════════════════════════════════
#  MENÚ INTERACTIVO CON FLECHAS + NÚMERO
#  Controles: ↑↓ · 1-9 · Enter
# ══════════════════════════════════════════════════════
ARROW_RESULT=0
arrow_menu() {
    local _am_title="$1"
    local -n _am_items="$2"
    local _am_sel=0
    local _am_count="${#_am_items[@]}"

    tput civis 2>/dev/null || true

    _am_draw() {
        tput rc 2>/dev/null || true
        echo -e " ${BOLD}${_am_title}${R}"
        label
        local _i
        for (( _i=0; _i<_am_count; _i++ )); do
            local _num=$(( _i + 1 ))
            if [[ $_i -eq $_am_sel ]]; then
                printf "  ${BG_CYAN}${C_WHITE}${BOLD} %d ❯ %-65s${R}\n" \
                    "$_num" "${_am_items[$_i]}"
            else
                printf "  ${C_GRAY}  %d   %-65s${R}\n" \
                    "$_num" "${_am_items[$_i]}"
            fi
        done
        echo
    }

    tput sc 2>/dev/null || true
    _am_draw

    local _key _esc
    while true; do
        IFS= read -rsn1 _key
        case "$_key" in
            $'\x1b')
                IFS= read -rsn1 -t 0.15 _esc || continue
                if [[ "$_esc" == "[" ]]; then
                    IFS= read -rsn1 -t 0.15 _esc || continue
                    case "$_esc" in
                        A) if (( _am_sel > 0 )); then
                               _am_sel=$(( _am_sel - 1 ))
                           fi; _am_draw ;;
                        B) if (( _am_sel < _am_count - 1 )); then
                               _am_sel=$(( _am_sel + 1 ))
                           fi; _am_draw ;;
                    esac
                fi ;;
            [1-9])
                local _num_sel=$(( _key - 1 ))
                if (( _num_sel >= 0 && _num_sel < _am_count )); then
                    _am_sel=$_num_sel
                    _am_draw
                fi ;;
            "")
                break ;;
        esac
    done

    tput cnorm 2>/dev/null || true
    ARROW_RESULT=$_am_sel
}

# ══════════════════════════════════════════════════════
#  PAQUETES
# ══════════════════════════════════════════════════════
PACMAN_PACKAGES=(
    # Drivers Gráficos AMD Ryzen (¡Añadidos aquí!)
    mesa
    lib32-mesa
    vulkan-radeon
    lib32-vulkan-radeon
    libva-mesa-driver
    libva-utils

    # Hyprland + portales
    hyprland
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    hyprpolkitagent

    # Terminal y utilidades
    kitty
    fastfetch

    # Herramientas base
    git wget curl unzip 7zip btop
    ripgrep fd fzf eza

    # Fuentes
    ttf-jetbrains-mono-nerd
    noto-fonts
    noto-fonts-cjk
    noto-fonts-extra
    noto-fonts-emoji

    # Gestor de archivos / visor
    yazi
    imv

    # Wallpaper y shell
    awww
    quickshell

    # Clipboard + brillo + media
    wl-clipboard
    brightnessctl
    playerctl

    # Screenshots
    grim slurp

    # Audio
    pipewire wireplumber pipewire-pulse pipewire-alsa pipewire-jack

    # Display manager
    sddm

    # Sistema
    power-profiles-daemon
    xdg-user-dirs

    # GTK settings (Wayland)
    nwg-look
    gnome-themes-extra

    # Editor gráfico
    zed

    # Languages
    rustup
)

# ══════════════════════════════════════════════════════
#  BLOQUE 1 — VERIFICACIONES
# ══════════════════════════════════════════════════════
check_requirements() {
    screen "Verificaciones del sistema" 1 9

    info "Verificando que no seas root..."
    if [[ $EUID -eq 0 ]]; then
        fail "No ejecutes este script como root. Corre como tu usuario normal."
    fi
    ok "Usuario normal detectado: ${BOLD}$(whoami)${R}"

    info "Verificando sudo..."
    if ! sudo -v 2>/dev/null; then
        fail "No tenés acceso a sudo. Verificá que tu usuario esté en el grupo wheel."
    fi
    ok "sudo disponible."

    info "Verificando conexión a internet..."
    if ! ping -c 1 -W 3 archlinux.org &>/dev/null; then
        fail "Sin conexión a internet. Verificá tu red y vuelve a correr el script."
    fi
    ok "Conexión a internet detectada."

    sleep 0.5
}

# ══════════════════════════════════════════════════════
#  BLOQUE 2 — pacman.conf
#  · Descomentar Color
#  · Agregar ILoveCandy debajo de Color
#  · Descomentar repositorio multilib
# ══════════════════════════════════════════════════════
configure_pacman() {
    screen "Configurando pacman.conf" 2 9

    info "Habilitando Color en pacman.conf..."
    if grep -q "^Color" /etc/pacman.conf; then
        ok "Color ya estaba habilitado."
    else
        sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
        ok "Color habilitado."
    fi

    info "Agregando ILoveCandy..."
    if grep -q "^ILoveCandy" /etc/pacman.conf; then
        ok "ILoveCandy ya estaba presente."
    else
        # Inserta ILoveCandy en la línea inmediatamente después de Color
        sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
        ok "ILoveCandy agregado."
    fi

    info "Habilitando repositorio multilib (soporte 32 bits)..."
    if grep -q "^\[multilib\]" /etc/pacman.conf; then
        ok "multilib ya estaba habilitado."
    else
        # Descomenta [multilib] y su Include = ...
        sudo sed -i '/^#\[multilib\]/{
            s/^#//
            n
            s/^#//
        }' /etc/pacman.conf
        ok "multilib habilitado."
    fi

    info "Actualizando base de datos de pacman..."
    sudo pacman -Sy --noconfirm
    ok "Base de datos actualizada."

    sleep 0.5
}

# ══════════════════════════════════════════════════════
#  BLOQUE 3 — Actualización del sistema
# ══════════════════════════════════════════════════════
update_system() {
    screen "Actualizando el sistema" 3 9

    info "Ejecutando pacman -Syu..."
    newline
    sudo pacman -Syu --noconfirm
    ok "Sistema actualizado."

    sleep 0.5
}

# ══════════════════════════════════════════════════════
#  BLOQUE 4 — Instalación de paquetes
# ══════════════════════════════════════════════════════
install_packages() {
    screen "Instalando paquetes" 4 9

    info "Paquetes a instalar:"
    newline
    # Muestra la lista en columnas de forma legible
    printf "  ${C_GRAY}"
    printf "%s  " "${PACMAN_PACKAGES[@]}"
    printf "${R}\n"
    newline

    # Construir el string de paquetes para pacman
    local pkg_list="${PACMAN_PACKAGES[*]}"

    info "Instalando con pacman (esto puede tomar varios minutos)..."
    newline
    # shellcheck disable=SC2086
    sudo pacman -S --needed --noconfirm $pkg_list

    ok "Todos los paquetes instalados."
    sleep 0.5
}

# ══════════════════════════════════════════════════════
#  BLOQUE 5 — LazyVim
# ══════════════════════════════════════════════════════
install_lazyvim() {
    screen "Configurando LazyVim" 5 9

    if [[ -d "$HOME/.config/nvim" ]]; then
        warn "Ya existe ~/.config/nvim."
        newline
        local opts=(
            "Reemplazar con LazyVim (borra la carpeta actual)"
            "Omitir — mantener lo que hay"
        )
        arrow_menu "¿Qué deseas hacer?" opts
        if [[ "$ARROW_RESULT" -eq 1 ]]; then
            ok "LazyVim omitido."
            sleep 0.5
            return
        fi
        info "Eliminando ~/.config/nvim existente..."
        rm -rf "$HOME/.config/nvim"
        ok "Carpeta eliminada."
    fi

    info "Clonando LazyVim starter en ~/.config/nvim..."
    git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"

    info "Eliminando .git del starter para vincular tu propio repo luego..."
    rm -rf "$HOME/.config/nvim/.git"

    ok "LazyVim listo."
    echo -e "  ${C_GRAY}  Ejecuta ${BOLD}nvim${R}${C_GRAY} para que instale sus plugins automáticamente.${R}"
    sleep 0.5
}

# ══════════════════════════════════════════════════════
#  BLOQUE 6 — Servicios
#
#  SDDM: solo enable (sin --now). No tiene sentido iniciarlo ahora porque
#        aún no hay sesión gráfica activa — arrancará en el próximo boot.
#
#  Pipewire/power-profiles: enable --now porque sí corren en sesión de usuario
#        y se pueden levantar sin reiniciar.
#
#  Todos se verifican antes de activar para no fallar si ya están corriendo.
# ══════════════════════════════════════════════════════

# Verifica y activa un servicio de sistema (sudo)
_svc_system() {
    local svc="$1" action="${2:---now}"
    if [[ "$action" == "--enable-only" ]]; then
        if sudo systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            ok "${svc} ya estaba habilitado."
        else
            sudo systemctl enable "$svc"
            ok "${svc} habilitado — activo en el próximo boot."
        fi
    else
        if sudo systemctl is-active --quiet "$svc" 2>/dev/null; then
            ok "${svc} ya está activo."
        else
            sudo systemctl enable --now "$svc"
            ok "${svc} habilitado y activo."
        fi
    fi
}

# Verifica y activa un servicio de usuario (sin sudo)
_svc_user() {
    local svc="$1"
    if systemctl --user is-active --quiet "$svc" 2>/dev/null; then
        ok "${svc} ya está activo."
    else
        systemctl --user enable --now "$svc"
        ok "${svc} habilitado y activo."
    fi
}

enable_services() {
    screen "Habilitando servicios" 6 9

    info "SDDM (display manager) — solo habilitar, inicia en el próximo boot..."
    _svc_system sddm --enable-only

    newline
    info "power-profiles-daemon..."
    _svc_system power-profiles-daemon

    newline
    info "Pipewire (servicios de sesión de usuario)..."
    _svc_user pipewire
    _svc_user wireplumber
    _svc_user pipewire-pulse

    sleep 0.5
}

# ══════════════════════════════════════════════════════
#  BLOQUE 7 — Directorios de usuario
# ══════════════════════════════════════════════════════
setup_user_dirs() {
    screen "Directorios de usuario" 7 9

    info "Ejecutando xdg-user-dirs-update..."
    xdg-user-dirs-update
    ok "Directorios creados:"
    newline
    # Mostrar los directorios definidos
    while IFS='=' read -r key val; do
        [[ "$key" =~ ^XDG_ ]] || continue
        val="${val//\"/}"
        val="${val/#\$HOME/$HOME}"
        printf "  ${C_GRAY}%-30s${R} %s\n" "$key" "$val"
    done < "$HOME/.config/user-dirs.dirs"

    sleep 0.5
}

# ══════════════════════════════════════════════════════
#  BLOQUE 8 — AUR Helper
# ══════════════════════════════════════════════════════
install_aur_helper() {
    screen "AUR Helper" 8 9

    info "Un AUR helper te permite instalar paquetes del Arch User Repository"
    info "con la misma comodidad que pacman."
    newline

    local opts=(
        "paru  — Rust · más moderno · API compatible con yay · activamente mantenido"
        "yay   — Go · el más conocido · más ejemplos en foros y wikis"
        "Omitir — instalar el helper más adelante manualmente"
    )
    arrow_menu "¿Qué AUR helper querés instalar?" opts

    case "$ARROW_RESULT" in
        0) _install_paru ;;
        1) _install_yay  ;;
        2)
            warn "AUR helper omitido."
            echo -e "  ${C_GRAY}  Podés instalarlo después siguiendo las instrucciones en aur.archlinux.org${R}"
            sleep 1
            return
            ;;
    esac
}

_install_paru() {
    if command -v paru &>/dev/null; then
        ok "paru ya está instalado."
        sleep 0.5
        return
    fi

    info "Instalando dependencias de compilación..."
    sudo pacman -S --needed --noconfirm base-devel

    info "Clonando paru desde AUR..."
    local _dir
    _dir="$(mktemp -d)"
    git clone https://aur.archlinux.org/paru.git "$_dir/paru"

    info "Compilando e instalando paru..."
    newline
    cd "$_dir/paru"
    makepkg -si
    cd "$HOME"
    rm -rf "$_dir"

    ok "paru instalado correctamente."
    sleep 0.5
}

_install_yay() {
    if command -v yay &>/dev/null; then
        ok "yay ya está instalado."
        sleep 0.5
        return
    fi

    info "Instalando dependencias de compilación y clonando yay..."
    local _dir
    _dir="$(mktemp -d)"
    # Comando exacto de la documentación oficial de yay
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git "$_dir/yay"

    info "Compilando e instalando yay..."
    newline
    cd "$_dir/yay"
    makepkg -si
    cd "$HOME"
    rm -rf "$_dir"

    ok "yay instalado correctamente."
    sleep 0.5
}

# ══════════════════════════════════════════════════════
#  BLOQUE 9 — Resumen y cierre
# ══════════════════════════════════════════════════════
finish() {
    screen "¡Post-instalación completa!" 9 9

    echo -e "  ${BOLD}${C_GREEN}✔  El sistema está listo.${R}"
    newline
    label

    newline
    echo -e "  ${BOLD}${C_CYAN}ENTORNO${R}"
    echo -e "  ${C_GRAY}  ├─ Compositor  ${R}${BOLD}Hyprland${R}${C_GRAY}  (config manual → ~/.config/hypr/)${R}"
    echo -e "  ${C_GRAY}  ├─ Terminal    ${R}${BOLD}Kitty${R}${C_GRAY}  · JetBrains Mono Nerd Font${R}"
    echo -e "  ${C_GRAY}  ├─ Login       ${R}${BOLD}SDDM${R}${C_GRAY}  · activo en el próximo boot${R}"
    echo -e "  ${C_GRAY}  ├─ Wallpaper   ${R}${BOLD}awww${R}"
    echo -e "  ${C_GRAY}  └─ Shell UI    ${R}${BOLD}Quickshell${R}"

    newline
    echo -e "  ${BOLD}${C_CYAN}HERRAMIENTAS${R}"
    echo -e "  ${C_GRAY}  ├─ Editor      ${R}${BOLD}Neovim${R}${C_GRAY}  + LazyVim${R}"
    echo -e "  ${C_GRAY}  ├─ Archivos    ${R}${BOLD}yazi${R}${C_GRAY}  + ${R}${BOLD}imv${R}"
    echo -e "  ${C_GRAY}  ├─ Audio       ${R}${BOLD}Pipewire${R}${C_GRAY}  + WirePlumber${R}"
    echo -e "  ${C_GRAY}  ├─ Búsqueda    ${R}${BOLD}ripgrep${R}${C_GRAY}  · ${R}${BOLD}fd${R}${C_GRAY}  · ${R}${BOLD}fzf${R}"
    echo -e "  ${C_GRAY}  └─ Listado     ${R}${BOLD}eza${R}${C_GRAY}  (reemplazo moderno de ls)${R}"

    newline
    echo -e "  ${BOLD}${C_CYAN}SISTEMA${R}"
    echo -e "  ${C_GRAY}  ├─ pacman.conf  ${R}Color${C_GRAY}  +  ${R}ILoveCandy${C_GRAY}  +  ${R}multilib${R}"
    echo -e "  ${C_GRAY}  ├─ Energía      ${R}power-profiles-daemon${R}"
    echo -e "  ${C_GRAY}  └─ Directorios  ${R}xdg-user-dirs${C_GRAY}  configurados${R}"

    newline
    label
    newline
    echo -e "  ${BOLD}${C_YELLOW}PRÓXIMOS PASOS${R}"
    echo -e "  ${C_GRAY}  1. Creá ${R}${BOLD}~/.config/hypr/hyprland.lua${R}${C_GRAY} con tu config Lua${R}"
    echo -e "  ${C_GRAY}  2. Ejecutá ${R}${BOLD}nvim${R}${C_GRAY} para que LazyVim instale sus plugins${R}"
    echo -e "  ${C_GRAY}  3. Reiniciá para entrar a Hyprland desde SDDM${R}"
    newline
    label
    newline

    local opts=(
        "Reiniciar ahora"
        "Salir sin reiniciar"
    )
    arrow_menu "¿Qué deseas hacer?" opts

    if [[ "$ARROW_RESULT" -eq 0 ]]; then
        ok "Reiniciando en 3 segundos..."
        sleep 3
        sudo reboot
    else
        warn "Recordá reiniciar cuando estés listo con: ${BOLD}sudo reboot${R}"
    fi
}

# ══════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════
main() {
    check_requirements
    configure_pacman
    update_system
    install_packages
    install_lazyvim
    enable_services
    setup_user_dirs
    install_aur_helper
    finish
}

main "$@"
