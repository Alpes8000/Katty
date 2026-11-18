#!/usr/bin/env bash
# ============================================================
#  install.sh — Kitty + Zsh + Powerlevel10k "Katty Noir"  (v3)
#
#  Installe : kitty, zsh, JetBrainsMono Nerd Font Mono, Powerlevel10k,
#  zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions,
#  zsh-history-substring-search, fzf-tab, fzf-git, fzf, eza, bat,
#  ripgrep, fd, zoxide, delta
#  Supporte : Fedora (dnf), Debian/Ubuntu (apt), Arch (pacman), openSUSE (zypper)
#
#  Usage : chmod +x install.sh && ./install.sh [options]
#    -y, --yes          zsh en shell par défaut sans poser la question
#    --no-sudo          n'installe aucun paquet système (tout le reste en local)
#    --kitty-official   installe la dernière version officielle de kitty dans
#                       ~/.local (utile si la distribution fournit un vieux kitty)
#    --restore [DOSSIER] remet les fichiers de la dernière sauvegarde
#                       (~/.config-backup-*) ou de DOSSIER, puis s'arrête
#    -h, --help         cette aide
#
#  Relançable à volonté : un fichier déjà à jour n'est pas touché, les plugins
#  sont mis à jour, et les anciens fichiers sont sauvegardés dans
#  ~/.config-backup-<date> avant d'être remplacés.
#
#  Panneaux kitty "responsive" (katty.py) : un nouveau panneau n'est jamais
#  plus petit que 30 colonnes x 7 lignes, quel que soit l'écran ; sans place,
#  il s'ouvre dans un nouvel onglet ; si la fenêtre rétrécit trop, zoom
#  automatique sur le panneau actif. Corrige l'écran "rayé" après plusieurs
#  ctrl+shift+entrée (panneaux devenus plus étroits que leurs propres marges).
# ============================================================
set -Eeuo pipefail

C_PINK=$'\e[38;2;224;18;71m'; C_GREEN=$'\e[32m'; C_YEL=$'\e[33m'; C_RED=$'\e[31m'
C_DIM=$'\e[2m'; C_BOLD=$'\e[1m'; C_OFF=$'\e[0m'
if [[ ! -t 1 ]]; then C_PINK= C_GREEN= C_YEL= C_RED= C_DIM= C_BOLD= C_OFF=; fi
info() { printf '\n%s==>%s %s%s%s\n' "$C_PINK" "$C_OFF" "$C_BOLD" "$*" "$C_OFF"; }
ok()   { printf '%s ✔%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
warn() { printf '%s !%s %s\n' "$C_YEL" "$C_OFF" "$*"; }
die()  { printf '%s ✘%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

usage() { sed -n '/^#  Usage/,/^#    -h/p' "$0" | sed 's/^#  \{0,1\}//'; }

ASSUME_YES=0 NO_SUDO=0 KITTY_OFFICIAL=0 RESTORE=0 RESTORE_FROM=""
while (( $# )); do
  case $1 in
    -y|--yes)          ASSUME_YES=1 ;;
    --no-sudo)         NO_SUDO=1 ;;
    --kitty-official)  KITTY_OFFICIAL=1 ;;
    --restore)         RESTORE=1
                       if [[ -n ${2:-} && ${2:-} != -* ]]; then RESTORE_FROM=$2; shift; fi ;;
    -h|--help)         usage; exit 0 ;;
    *)                 die "Option inconnue : $1 (voir --help)" ;;
  esac
  shift
done

[[ $EUID -ne 0 ]] || die "Ne lance pas ce script en root (il utilise sudo quand il faut)."

ZSH_DIR="$HOME/.zsh"
KITTY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kitty"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/katty-install.log"
WORKDIR=$(mktemp -d)
SUDO_PID=""
ARCH=$(uname -m)
mkdir -p "${LOG%/*}" "$HOME/.local/bin"
: > "$LOG"
# Les outils installés en local (fzf récent, eza, liens bat/fd, kitty officiel)
# doivent être trouvés pendant l'installation
export PATH="$HOME/.local/bin:$PATH"
export GIT_TERMINAL_PROMPT=0

cleanup() {
  [[ -z $SUDO_PID ]] || kill "$SUDO_PID" 2>/dev/null || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT
trap 'die "Erreur ligne $LINENO (commande : $BASH_COMMAND) — journal : $LOG"' ERR

# ------------------------------------------------------------
#  Outils
# ------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

tilde() { printf '%s' "${1/#"$HOME"/'~'}"; }   # /home/moi/x → ~/x (affichage)

ver_ge() {  # ver_ge <version> <minimum> : vrai si version >= minimum
  [[ $(printf '%s\n%s\n' "$2" "$1" | sort -V | sed -n '1p') == "$2" ]]
}

backup() {  # backup <fichier> : copie le contenu actuel dans $BACKUP_DIR
  local f=$1
  [[ -e $f ]] || return 0
  mkdir -p "$BACKUP_DIR"
  cp -aL "$f" "$BACKUP_DIR/$(basename "$f")"
  ok "Sauvegarde de $(tilde "$f") → $(tilde "$BACKUP_DIR")"
}

install_conf() {  # install_conf <destination> <fonction qui écrit le contenu> [filtre]
  local dest=$1 writer=$2 filter=${3:-} tmp="$WORKDIR/conf.tmp"
  "$writer" "$tmp"
  [[ -z $filter ]] || "$filter" "$tmp"
  if [[ -f $dest ]] && cmp -s "$tmp" "$dest"; then
    ok "$(tilde "$dest") (déjà à jour)"
    return 0
  fi
  backup "$dest"
  mkdir -p "$(dirname "$dest")"
  cat "$tmp" > "$dest"
  rm -f "$dest.zwc"          # une version précompilée périmée passerait devant
  ok "$(tilde "$dest")"
}

clone() {  # clone <url> <dossier> : clone léger, ou mise à jour s'il existe
  if [[ -d $2/.git ]]; then
    git -C "$2" pull --ff-only -q || return 1
  else
    # dossier présent mais pas un dépôt git (copie manuelle, clone interrompu) : mis de côté
    [[ ! -e $2 ]] || mv "$2" "$2.old-$(date +%Y%m%d-%H%M%S)" || return 1
    git clone --depth=1 -q "$1" "$2" || return 1
  fi
}

link_alias() {  # link_alias <binaire réel> <nom voulu> (ex : batcat → bat sous Debian)
  have "$2" && return 0
  if have "$1"; then
    ln -sf "$(command -v "$1")" "$HOME/.local/bin/$2"
    ok "$2 → $1 (lien dans ~/.local/bin)"
  fi
}

fetch() {  # fetch <url> <fichier>
  curl -fsSL --retry 3 --connect-timeout 15 -o "$2" "$1"
}

# ------------------------------------------------------------
#  --restore : remettre une sauvegarde
# ------------------------------------------------------------
if (( RESTORE )); then
  src=$RESTORE_FROM
  if [[ -z $src ]]; then
    src=$(find "$HOME" -maxdepth 1 -type d -name '.config-backup-*' 2>/dev/null | sort | tail -n 1)
  fi
  [[ -n $src && -d $src ]] || die "Aucune sauvegarde trouvée (dossiers ~/.config-backup-*)."
  info "Restauration depuis $(tilde "$src")"
  restored=0
  for name in kitty.conf katty.py .p10k.zsh .zshrc; do
    [[ -f $src/$name ]] || continue
    case $name in
      kitty.conf|katty.py) dest="$KITTY_DIR/$name" ;;
      *)                     dest="$HOME/$name" ;;
    esac
    backup "$dest"                      # l'état actuel est sauvegardé aussi
    mkdir -p "$(dirname "$dest")"
    cp -f "$src/$name" "$dest"
    rm -f "$dest.zwc"
    ok "Restauré : $(tilde "$dest")"
    restored=1
  done
  (( restored )) || die "$src ne contient aucun fichier de configuration."
  rm -f "${XDG_CACHE_HOME:-$HOME/.cache}"/zsh/init-*.zsh
  printf '\nRelance kitty (ou `exec zsh`) pour retrouver l'\''ancienne configuration.\n'
  exit 0
fi

# ------------------------------------------------------------
#  1) Paquets système
# ------------------------------------------------------------
PM=""
if   have dnf;     then PM=dnf
elif have apt-get; then PM=apt
elif have pacman;  then PM=pacman
elif have zypper;  then PM=zypper
fi

pkg_install() {
  case $PM in
    dnf)    sudo dnf install -y "$@" ;;
    apt)    sudo apt-get install -y "$@" ;;
    pacman) sudo pacman -S --needed --noconfirm "$@" ;;
    zypper) sudo zypper --non-interactive install --no-recommends "$@" ;;
  esac
}

pkg_install_each() {  # tout d'un coup (rapide), sinon un par un (on repère les absents)
  if pkg_install "$@" >>"$LOG" 2>&1; then
    ok "$*"
    return 0
  fi
  local p
  for p in "$@"; do
    if pkg_install "$p" >>"$LOG" 2>&1; then ok "$p"; else warn "$p indisponible dans les dépôts"; fi
  done
}

if (( NO_SUDO )); then
  info "Paquets système : ignorés (--no-sudo)"
elif [[ -z $PM ]]; then
  warn "Gestionnaire de paquets non reconnu (dnf, apt, pacman, zypper) : paquets système ignorés."
  NO_SUDO=1
else
  have sudo || die "sudo est requis (ou relance avec --no-sudo)."
  info "Paquets système ($PM)"
  sudo -v || die "sudo refusé. Relance avec --no-sudo pour tout installer sans paquets système."
  printf '   installation en cours, détails dans %s\n' "$(tilde "$LOG")"
  # Garde la session sudo ouverte pendant toute l'installation
  ( while true; do sudo -n true; sleep 45; kill -0 "$$" 2>/dev/null || exit 0; done ) 2>/dev/null &
  SUDO_PID=$!

  case $PM in
    dnf)    BASE=(kitty zsh git curl unzip xz fontconfig util-linux-user)
            OPT=(fzf bat eza ripgrep fd-find zoxide git-delta libnotify) ;;
    apt)    BASE=(kitty zsh git curl unzip xz-utils fontconfig)
            OPT=(fzf bat eza ripgrep fd-find zoxide git-delta libnotify-bin) ;;
    pacman) BASE=(kitty zsh git curl unzip xz fontconfig)
            OPT=(fzf bat eza ripgrep fd zoxide git-delta libnotify) ;;
    zypper) BASE=(kitty zsh git curl unzip xz fontconfig)
            OPT=(fzf bat eza ripgrep fd zoxide git-delta libnotify-tools) ;;
  esac
  if (( KITTY_OFFICIAL )); then          # kitty viendra de l'installeur officiel
    keep=(); for p in "${BASE[@]}"; do [[ $p == kitty ]] || keep+=("$p"); done; BASE=("${keep[@]}")
  fi

  if [[ $PM == apt ]]; then sudo apt-get update -qq >>"$LOG" 2>&1 || warn "apt-get update a échoué (voir $LOG)"; fi
  pkg_install_each "${BASE[@]}"
  pkg_install_each "${OPT[@]}"
fi

# Debian/Ubuntu installent bat → batcat et fd → fdfind : on remet les vrais noms
link_alias batcat bat
link_alias fdfind fd

for c in zsh git curl; do
  have "$c" || die "$c est introuvable (installe-le puis relance le script)."
done

# ------------------------------------------------------------
#  2) Outils absents ou trop vieux : versions officielles dans ~/.local
# ------------------------------------------------------------
info "Outils en ligne de commande"

# fzf ≥ 0.48 : `fzf --zsh`, fzf-git, recherche live (frg)
fzf_ver=$(fzf --version 2>/dev/null | awk '{print $1}') || fzf_ver=""
if [[ -n $fzf_ver ]] && ver_ge "$fzf_ver" 0.48; then
  ok "fzf $fzf_ver"
elif clone https://github.com/junegunn/fzf.git "$HOME/.fzf" >>"$LOG" 2>&1 &&
     "$HOME/.fzf/install" --bin >>"$LOG" 2>&1 && [[ -x $HOME/.fzf/bin/fzf ]]; then
  ln -sf "$HOME/.fzf/bin/fzf" "$HOME/.local/bin/fzf"
  ok "fzf $("$HOME/.fzf/bin/fzf" --version | awk '{print $1}') (version officielle, ~/.fzf)"
else
  warn "fzf récent introuvable${fzf_ver:+ (fzf $fzf_ver gardé)} : fzf-git et frg seront désactivés"
fi

# eza (absent de certaines distributions, ex. Fedora récente)
if have eza; then
  ok "eza"
else
  case $ARCH in
    x86_64)        eza_asset=eza_x86_64-unknown-linux-musl.tar.gz ;;
    aarch64|arm64) eza_asset=eza_aarch64-unknown-linux-gnu.tar.gz ;;
    *)             eza_asset="" ;;
  esac
  mkdir -p "$WORKDIR/eza"
  if [[ -n $eza_asset ]] &&
     fetch "https://github.com/eza-community/eza/releases/latest/download/$eza_asset" "$WORKDIR/eza.tgz" &&
     tar -xzf "$WORKDIR/eza.tgz" -C "$WORKDIR/eza" && [[ -f $WORKDIR/eza/eza ]]; then
    install -m 755 "$WORKDIR/eza/eza" "$HOME/.local/bin/eza"
    ok "eza (binaire officiel → ~/.local/bin)"
  else
    warn "eza indisponible : ls classique en couleur à la place"
  fi
fi

# zoxide (commande z)
if have zoxide; then
  ok "zoxide"
elif fetch https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh "$WORKDIR/zoxide.sh" &&
     sh "$WORKDIR/zoxide.sh" --bin-dir "$HOME/.local/bin" >>"$LOG" 2>&1 && have zoxide; then
  ok "zoxide (installeur officiel → ~/.local/bin)"
else
  warn "zoxide indisponible : la commande z sera absente"
fi

for c in bat rg fd delta; do
  have "$c" && ok "$c" || warn "$c absent (optionnel)"
done

# ------------------------------------------------------------
#  3) kitty
# ------------------------------------------------------------
if (( KITTY_OFFICIAL )); then
  info "kitty officiel (dernière version, dans ~/.local/kitty.app)"
  if fetch https://sw.kovidgoyal.net/kitty/installer.sh "$WORKDIR/kitty-installer.sh" &&
     sh "$WORKDIR/kitty-installer.sh" launch=n >>"$LOG" 2>&1; then
    ln -sf "$HOME/.local/kitty.app/bin/kitty" "$HOME/.local/kitty.app/bin/kitten" "$HOME/.local/bin/"
    APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    mkdir -p "$APPS"
    cp "$HOME"/.local/kitty.app/share/applications/kitty*.desktop "$APPS/"
    sed -i "s|Icon=kitty|Icon=$HOME/.local/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|g;
            s|Exec=kitty|Exec=$HOME/.local/kitty.app/bin/kitty|g" "$APPS"/kitty*.desktop
    ok "kitty $("$HOME/.local/bin/kitty" --version | awk '{print $2}') installé (raccourci du menu mis à jour)"
  else
    warn "Installation officielle de kitty impossible (voir $LOG)"
  fi
fi

KITTY_VER=""
if have kitty; then
  KITTY_VER=$(kitty --version 2>/dev/null | awk '{print $2}') || KITTY_VER=""
fi

# ------------------------------------------------------------
#  4) JetBrainsMono Nerd Font (variante Mono : icônes sur 1 cellule)
# ------------------------------------------------------------
info "Police JetBrainsMono Nerd Font Mono"
fc-list : family > "$WORKDIR/fonts.txt" 2>/dev/null || true
if grep -qi "JetBrainsMono Nerd Font Mono" "$WORKDIR/fonts.txt"; then
  ok "Déjà installée"
else
  FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/JetBrainsMonoNF"
  NF_URL=https://github.com/ryanoasis/nerd-fonts/releases/latest/download
  mkdir -p "$FONT_DIR"
  # .tar.xz : 7 Mo au lieu de 134 Mo pour le .zip
  if fetch "$NF_URL/JetBrainsMono.tar.xz" "$WORKDIR/jbm.tar.xz" &&
     tar -xJf "$WORKDIR/jbm.tar.xz" -C "$FONT_DIR" --wildcards 'JetBrainsMonoNerdFontMono-*.ttf'; then
    :
  elif fetch "$NF_URL/JetBrainsMono.zip" "$WORKDIR/jbm.zip" &&
       unzip -oq "$WORKDIR/jbm.zip" 'JetBrainsMonoNerdFontMono-*.ttf' -d "$FONT_DIR"; then
    :
  else
    die "Téléchargement de la police impossible (connexion ?)."
  fi
  fc-cache -f "$FONT_DIR" >/dev/null
  ok "Police installée dans $(tilde "$FONT_DIR")"
fi

# ------------------------------------------------------------
#  5) Powerlevel10k + plugins zsh (téléchargés en parallèle)
# ------------------------------------------------------------
info "Powerlevel10k et plugins zsh"
REPO_URLS=(romkatv/powerlevel10k zsh-users/zsh-autosuggestions zsh-users/zsh-syntax-highlighting
           zsh-users/zsh-completions zsh-users/zsh-history-substring-search Aloxaf/fzf-tab junegunn/fzf-git.sh)
REPO_DIRS=(powerlevel10k plugins/zsh-autosuggestions plugins/zsh-syntax-highlighting
           plugins/zsh-completions plugins/zsh-history-substring-search plugins/fzf-tab plugins/fzf-git)
mkdir -p "$ZSH_DIR/plugins"
pids=()
for i in "${!REPO_URLS[@]}"; do
  clone "https://github.com/${REPO_URLS[i]}.git" "$ZSH_DIR/${REPO_DIRS[i]}" >"$WORKDIR/clone-$i.log" 2>&1 &
  pids[i]=$!
done
for i in "${!pids[@]}"; do
  if wait "${pids[i]}"; then
    ok "${REPO_URLS[i]#*/}"
  elif [[ -d $ZSH_DIR/${REPO_DIRS[i]}/.git ]]; then
    warn "${REPO_URLS[i]} : mise à jour impossible, version actuelle conservée"
    cat "$WORKDIR/clone-$i.log" >>"$LOG"
  else
    warn "${REPO_URLS[i]} : téléchargement impossible (voir $LOG)"
    cat "$WORKDIR/clone-$i.log" >>"$LOG"
  fi
done
[[ -f $ZSH_DIR/powerlevel10k/powerlevel10k.zsh-theme ]] || die "Powerlevel10k est indispensable : vérifie la connexion puis relance."

# gitstatusd (statut git ultra-rapide du prompt) : téléchargé maintenant
# plutôt qu'au premier lancement de zsh
if [[ -x $ZSH_DIR/powerlevel10k/gitstatus/install ]]; then
  "$ZSH_DIR/powerlevel10k/gitstatus/install" >>"$LOG" 2>&1 && ok "gitstatusd prêt" ||
    warn "gitstatusd sera téléchargé au premier lancement de zsh"
fi

# Plugins précompilés (.zwc) : zsh les lit plus vite. Une version périmée
# (plugin mis à jour) est ignorée automatiquement par zsh.
zsh -fc 'for f; do [[ -r $f ]] && zcompile -- $f 2>/dev/null; done; true' zsh \
  "$ZSH_DIR"/plugins/*/*.zsh \
  "$ZSH_DIR"/plugins/zsh-syntax-highlighting/highlighters/*/*.zsh \
  "$ZSH_DIR"/plugins/fzf-git/fzf-git.sh 2>/dev/null || true
ok "Plugins précompilés"

# ------------------------------------------------------------
#  6) Fichiers de configuration
# ------------------------------------------------------------
write_kitty_conf() {
  cat > "$1" <<'__KITTY_CONF__'
# ============================================================
#  kitty.conf — "Katty Noir"  (v3)
#  Fond noir transparent, accent rose #e01247, JetBrainsMono NF
#  Recharger : ctrl+shift+f5   ·   Aide-mémoire : `katty` dans le shell
#
#  ── Panneaux "responsive" (katty.py) ── lettres/flèches : marche en AZERTY ──
#   ctrl+shift+enter      nouveau panneau : coupe le côté le plus long ; si le
#                         panneau est trop petit, coupe le plus grand de l'onglet ;
#                         s'il n'y a plus de place : nouvel onglet. Jamais de
#                         panneau sous 30 colonnes x 7 lignes, sur aucun écran.
#   ctrl+shift+l          nouveau panneau À DROITE   (L = Latéral)
#   ctrl+shift+d          nouveau panneau EN DESSOUS (D = Dessous)
#   ctrl+alt+h/j/k/l      aller au panneau gauche / bas / haut / droite
#   ctrl+alt+shift+h/l    panneau plus étroit / plus large
#   ctrl+alt+shift+j/k    panneau plus haut / moins haut
#   ctrl+shift+z          zoom du panneau (aller-retour)
#   ctrl+shift+o          pivoter le split (côte à côte <-> empilé)
#   ctrl+shift+b          rééquilibrer tous les panneaux
#   ctrl+shift+f7 / f8    choisir un panneau par numéro / échanger deux panneaux
#   ctrl+shift+r          mode redimensionnement interactif
#   ctrl+shift+w          fermer le panneau
#  ── Onglets & fenêtres ──
#   ctrl+shift+t          nouvel onglet (même dossier)
#   alt+1 … alt+9         aller à l'onglet n (en AZERTY : alt+& é " ' ( - è _ ç)
#   ctrl+shift+← / →      onglet précédent / suivant
#   ctrl+shift+alt+t      renommer l'onglet
#   ctrl+shift+n          nouvelle fenêtre (même dossier)
#  ── Historique & recherche ──
#   ctrl+shift+f          chercher dans l'historique du terminal
#   ctrl+shift+↑ / ↓      sauter au prompt précédent / suivant
#   ctrl+shift+g          sortie de la dernière commande dans un pager
#   ctrl+shift+h          tout l'historique dans un pager
#   ctrl+shift+m          surligner flags CTF (jaune), IP (bleu), erreurs (rose)
#  ── Divers ──
#   ctrl+shift+e          ouvrir une URL affichée à l'écran
#   ctrl+shift+p > f      insérer un chemin affiché (p > l : une ligne, p > w : un mot)
#   ctrl+shift+u          saisir un caractère Unicode / emoji
#   ctrl+shift+delete     effacer l'écran
#   ctrl+shift+= / - / ⌫  police plus grande / plus petite / par défaut
#   ctrl+shift+a > m / l  plus / moins transparent
# ============================================================

# ------------------------------------------------------------
#  Fenêtre & layout
# ------------------------------------------------------------
initial_window_width          125c
initial_window_height         34c
remember_window_size          no
# Padding généreux avec un seul panneau, serré dès qu'on divise : dans un
# split chaque pixel compte (un padding plus large que le panneau = rendu cassé)
single_window_padding_width   8 12
window_padding_width          4 6
window_margin_width           0
draw_minimal_borders          yes
window_border_width           1.5pt
# Confirmation seulement si une commande tourne (shell au repos : on ferme direct)
confirm_os_window_close       -1
# hide_window_decorations     yes      # décommente pour supprimer la barre de titre
wayland_titlebar_color        background

# Transparence : noir pur (le flou ne marche que sous KDE / macOS, ignoré ailleurs)
background_opacity            0.78
background_blur               24
dynamic_background_opacity    yes

# Panneaux inactifs légèrement estompés
inactive_text_alpha           0.72

# Layouts : splits (par défaut) + zoom (stack)
enabled_layouts               splits,stack
# Garde-fou : si la fenêtre rétrécit trop pour ses panneaux, zoom automatique
# sur le panneau actif, et retour aux panneaux quand la place revient
watcher                       katty.py
# Un panneau qui grandit (split fermé, zoom) récupère son historique en haut
scrollback_fill_enlarged_window yes

# ------------------------------------------------------------
#  Police
# ------------------------------------------------------------
font_family                   JetBrainsMono Nerd Font Mono
bold_font                     auto
italic_font                   auto
bold_italic_font              auto
font_size                     12.0
# Ligatures actives sauf sous le curseur
# (kitty ne gère PAS les commentaires en fin de ligne : la v2 avait
#  « cursor   # … » ici, et l'option était ignorée sans aucun message)
disable_ligatures             cursor

# ------------------------------------------------------------
#  Curseur
# ------------------------------------------------------------
cursor                        #e01247
cursor_text_color             #ffffff
cursor_shape                  block
cursor_shape_unfocused        hollow
cursor_blink_interval         0.6
cursor_stop_blinking_after    15
# Traînée : seulement quand le curseur saute d'au moins 2 cases
cursor_trail                  13
cursor_trail_start_threshold  2
cursor_trail_decay            0.08 0.13

# ------------------------------------------------------------
#  Shell & terminal
# ------------------------------------------------------------
shell                         zsh
term                          xterm-256color
shell_integration             enabled
allow_remote_control          no
update_check_interval         0
# Notification bureau quand une commande de plus de 20 s se termine
# dans un onglet/panneau qu'on ne voit pas (cargo build, scan, etc.)
notify_on_cmd_finish          invisible 20

# ------------------------------------------------------------
#  Scrollback, souris, presse-papier
# ------------------------------------------------------------
scrollback_lines              20000
scrollback_pager_history_size 8
copy_on_select                clipboard
strip_trailing_spaces         smart
mouse_hide_wait               2.0
detect_urls                   yes
url_style                     curly
url_color                     #61afef
show_hyperlink_targets        yes
select_by_word_characters     @-./_~?&=%+#
# Barre de défilement fine, visible seulement quand on remonte l'historique
scrollbar                     scrolled
scrollbar_handle_color        #e01247
scrollbar_handle_opacity      0.7
scrollbar_width               0.4

# ------------------------------------------------------------
#  Cloche & synchro écran
# ------------------------------------------------------------
enable_audio_bell             no
visual_bell_duration          0.0
sync_to_monitor               yes

# ------------------------------------------------------------
#  Onglets (style powerline arrondi, masqués s'il n'y en a qu'un)
#  󰕰 n = nombre de panneaux · 󰊓 n = zoom avec n panneaux masqués
# ------------------------------------------------------------
tab_bar_edge                  bottom
tab_bar_style                 powerline
tab_powerline_style           round
tab_bar_min_tabs              2
tab_bar_margin_height         4.0 4.0
tab_title_max_length          32
tab_activity_symbol           "● "
bell_on_tab                   "󰂞 "
tab_title_template            "{fmt.fg._6b7280}{index}{fmt.fg.tab} {bell_symbol}{activity_symbol}{title}{fmt.fg._6b7280}{(' 󰊓 ' if layout_name == 'stack' else ' 󰕰 ') + str(num_windows) if num_windows > 1 else ''} "
active_tab_title_template     " {index} {bell_symbol}{title}{(' 󰊓 ' if layout_name == 'stack' else ' 󰕰 ') + str(num_windows) if num_windows > 1 else ''} "
active_tab_foreground         #ffffff
active_tab_background         #e01247
active_tab_font_style         bold
inactive_tab_foreground       #b1b8c9
inactive_tab_background       #1a1a1a
inactive_tab_font_style       normal
tab_bar_background            none

# ------------------------------------------------------------
#  Couleurs — Katty Noir
# ------------------------------------------------------------
background                    #000000
foreground                    #e6e6e6

selection_background          #e01247
selection_foreground          #ffffff

active_border_color           #e01247
inactive_border_color         #2a2a2a
bell_border_color             #e5c07b

# Surlignage ctrl+shift+m : 1 = flags CTF, 2 = adresses IP, 3 = erreurs
mark1_foreground              #000000
mark1_background              #e5c07b
mark2_foreground              #000000
mark2_background              #61afef
mark3_foreground              #ffffff
mark3_background              #e01247

# Black
color0                        #1a1a1a
color8                        #6b7280
# Red (accent rose)
color1                        #e01247
color9                        #ff2d55
# Green
color2                        #98c379
color10                       #b5e48c
# Yellow
color3                        #e5c07b
color11                       #f1d39b
# Blue
color4                        #61afef
color12                       #82bdf0
# Magenta
color5                        #c678dd
color13                       #d796e9
# Cyan
color6                        #56b6c2
color14                       #70c6d2
# White
color7                        #b1b8c9
color15                       #ffffff

# ------------------------------------------------------------
#  Raccourcis
#  (ctrl+shift+minus / equal / backspace gardent leurs réglages
#   par défaut de kitty pour la taille de police)
# ------------------------------------------------------------
# Panneaux "responsive" : jamais de panneau trop petit (voir katty.py)
map ctrl+shift+enter          kitten katty.py split auto
map ctrl+shift+l              kitten katty.py split right
map ctrl+shift+d              kitten katty.py split down

# Navigation entre panneaux
map ctrl+alt+h                neighboring_window left
map ctrl+alt+l                neighboring_window right
map ctrl+alt+k                neighboring_window up
map ctrl+alt+j                neighboring_window down

# Redimensionnement (refusé s'il rendait un panneau inutilisable)
map ctrl+alt+shift+h          kitten katty.py resize narrower 3
map ctrl+alt+shift+l          kitten katty.py resize wider 3
map ctrl+alt+shift+j          kitten katty.py resize taller 2
map ctrl+alt+shift+k          kitten katty.py resize shorter 2

# Gestion des splits
map ctrl+shift+z              toggle_layout stack
map ctrl+shift+o              layout_action rotate
map ctrl+shift+b              resize_window reset
map ctrl+shift+f7             focus_visible_window
map ctrl+shift+f8             swap_with_window

# Onglets & fenêtres (dans le dossier courant)
map ctrl+shift+t              new_tab_with_cwd
map ctrl+shift+n              new_os_window_with_cwd
map alt+1                     goto_tab 1
map alt+2                     goto_tab 2
map alt+3                     goto_tab 3
map alt+4                     goto_tab 4
map alt+5                     goto_tab 5
map alt+6                     goto_tab 6
map alt+7                     goto_tab 7
map alt+8                     goto_tab 8
map alt+9                     goto_tab 9
# Même chose en AZERTY sans Maj (kitty lit le caractère de la touche)
map alt+&                     goto_tab 1
map alt+é                     goto_tab 2
map alt+"                     goto_tab 3
map alt+'                     goto_tab 4
map alt+(                     goto_tab 5
map alt+-                     goto_tab 6
map alt+è                     goto_tab 7
map alt+_                     goto_tab 8
map alt+ç                     goto_tab 9

# Recherche dans tout l'historique du terminal (ouvre le pager, tape le motif)
map ctrl+shift+f              search_scrollback

# Sauter d'un prompt à l'autre (nécessite shell_integration)
map ctrl+shift+up             scroll_to_prompt -1
map ctrl+shift+down           scroll_to_prompt 1

# Surligner flags CTF / IP / erreurs dans tout ce qui s'affiche (aller-retour)
map ctrl+shift+m              toggle_marker regex 1 (?i:flag|ctf|htb|thm|picoctf|fcsc|dghack|ecw|ductf)\\{[^}\\s]+\\} 2 \\b(?:(?:25[0-5]|2[0-4]\\d|1?\\d?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1?\\d?\\d)\\b 3 \\b(?:[Ee]rror|ERROR|[Ff]ailed|FAILED|[Dd]enied|[Pp]anic(?:ked)?|Traceback|[Ss]egmentation\\sfault)\\b
__KITTY_CONF__
}

write_katty_py() {
  cat > "$1" <<'__KATTY_PY__'
# ============================================================
#  katty.py — panneaux kitty "responsive"  (Katty Noir v3)
#
#  Un seul fichier, deux rôles :
#   • kitten  (raccourcis) : kitten katty.py split auto|right|down
#                            kitten katty.py resize narrower|wider|taller|shorter [pas]
#   • watcher (kitty.conf) : watcher katty.py
#
#  Le bug corrigé : dans le layout "splits", kitty coupe toujours le panneau
#  actif en deux, sans aucun minimum. Au bout de quelques splits, un panneau
#  devient plus étroit que son propre padding : kitty lui calcule alors un
#  nombre de colonnes NÉGATIF et le rendu part en vrille (glyphes étirés en
#  rayures sur toute la fenêtre).
#
#  Les règles sont exprimées en CELLULES de texte, donc valables quels que
#  soient l'écran, la définition, le scaling ou la taille de police :
#   1. split   : seulement si les deux moitiés gardent MIN_COLS x MIN_LINES.
#                Sinon on coupe le plus grand panneau de l'onglet ; s'il n'y
#                a plus de place nulle part : nouvel onglet (même dossier).
#   2. resize  : annulé s'il ferait passer un panneau sous HARD_COLS x HARD_LINES.
#   3. fenêtre : si la fenêtre kitty rétrécit (demi-écran, petit moniteur…)
#                au point qu'un panneau passe sous ce plancher, les tailles
#                sont égalisées ; si ça ne suffit pas : zoom automatique sur
#                le panneau actif. Les panneaux reviennent tout seuls quand
#                la place revient (ou avec ctrl+shift+z).
# ============================================================

import time
import weakref

MIN_COLS, MIN_LINES = 30, 7      # taille minimale d'un panneau créé par un split
HARD_COLS, HARD_LINES = 10, 3    # plancher absolu : en dessous, zoom automatique
RESTORE_MARGIN = 1.15            # marge avant de quitter le zoom auto (anti yo-yo)
NOTIFY = True                    # notification bureau au premier zoom automatique


def _log(*args):
    try:
        from kitty.utils import log_error
        log_error('[katty]', *args)
    except Exception:
        pass


# ------------------------------------------------------------------
#  Géométrie
# ------------------------------------------------------------------
def _outer(g):
    """Boîte complète d'un panneau (texte + padding + bordure), en pixels."""
    sp = g.spaces
    return g.left - sp.left, g.top - sp.top, g.right + sp.right, g.bottom + sp.bottom


def _size(g):
    x0, y0, x1, y1 = _outer(g)
    return x1 - x0, y1 - y0


def _cell_size(win):
    try:
        from kitty.fast_data_types import cell_size_for_window
        cw, ch = cell_size_for_window(win.os_window_id)
        if cw > 0 and ch > 0:
            return cw, ch
    except Exception:
        pass
    g = win.geometry
    if g.xnum > 0 and g.ynum > 0:
        return max(1, (g.right - g.left) // g.xnum), max(1, (g.bottom - g.top) // g.ynum)
    return 10, 20


def _deco(win):
    """Pixels perdus autour du texte d'un panneau quand l'onglet en contient
    plusieurs : (horizontal, vertical, épaisseur d'une bordure)."""
    try:
        from kitty.fast_data_types import get_options, pt_to_px
        o, osw = get_options(), win.os_window_id
        p, m = o.window_padding_width, o.window_margin_width
        b = int(win.effective_border())

        def px(v):
            return pt_to_px(v, osw) if v > 0 else 0
        return (px(p.left) + px(p.right) + px(m.left) + px(m.right) + 2 * b,
                px(p.top) + px(p.bottom) + px(m.top) + px(m.bottom) + 2 * b, b)
    except Exception:
        sp = win.geometry.spaces
        return sp.left + sp.right, sp.top + sp.bottom, 2


def _after_split(win, horizontal, cell, deco):
    """(colonnes, lignes) de chacune des deux moitiés si on coupe `win`."""
    cw, ch = cell
    dx, dy, b = deco
    w, h = _size(win.geometry)
    if horizontal:              # côte à côte
        w = (w - 2 * b) // 2
    else:                       # l'un sous l'autre
        h = (h - 2 * b) // 2
    return (w - dx) // cw, (h - dy) // ch


def _direction(win, want, cell, deco):
    """True = côte à côte, False = empilé, None = impossible sans passer
    sous MIN_COLS x MIN_LINES. Par défaut on coupe le côté le plus long."""
    w, h = _size(win.geometry)
    wide = w >= h
    order = {'right': (True, False), 'down': (False, True)}.get(want, (wide, not wide))
    for horizontal in order:
        cols, lines = _after_split(win, horizontal, cell, deco)
        if cols >= MIN_COLS and lines >= MIN_LINES:
            return horizontal
    return None


# ------------------------------------------------------------------
#  Onglets et panneaux
# ------------------------------------------------------------------
def _layout_name(tab):
    try:
        return tab.current_layout.name
    except Exception:
        return ''


def _enabled(tab, name):
    """Nom complet du layout `name` s'il est activé dans l'onglet ('' sinon)."""
    for full in getattr(tab, 'enabled_layouts', ()):
        if full.partition(':')[0] == name:
            return full
    return ''


def _groups(tab):
    try:
        return [g for g in tab.windows.iter_all_layoutable_groups(only_visible=True) if g.geometry]
    except Exception:
        return []


def _all_fit(tab, cols, lines):
    for g in _groups(tab):
        if g.geometry.xnum < cols or g.geometry.ynum < lines:
            return False
    return True


def _launch(boss, src, *extra):
    """Lance un shell via la commande interne `launch` (pas besoin
    d'allow_remote_control : l'appel ne sort pas de kitty)."""
    args = ('launch', '--cwd=current') + extra
    try:
        boss.call_remote_control(src, args)
        return True
    except Exception as e:
        _log('launch', ' '.join(args), 'a échoué :', e)
    try:  # vieux kitty sans call_remote_control ni --next-to
        boss.launch(*[a for a in args[1:] if not a.startswith('--next-to')])
        return True
    except Exception as e:
        _log('repli launch impossible :', e)
    return False


def _split(boss, win, tab, want):
    if win is None or tab is None:
        return _launch(boss, win)
    if _layout_name(tab) == 'stack' and _enabled(tab, 'splits'):
        if getattr(tab, '_katty_autozoom', None):
            # zoom automatique = la fenêtre est déjà trop petite pour cet onglet
            return _launch(boss, win, '--type=tab')
        tab.goto_layout(_enabled(tab, 'splits'))      # zoom manuel : on dézoome
    if _layout_name(tab) != 'splits':
        return _launch(boss, win)                     # autre layout : défaut kitty

    cell, deco = _cell_size(win), _deco(win)
    d = _direction(win, want, cell, deco)
    if d is not None:
        return _launch(boss, win, '--location=' + ('vsplit' if d else 'hsplit'))

    # Panneau actif trop petit : on coupe le plus grand panneau de l'onglet
    groups = sorted(_groups(tab), key=lambda g: _size(g.geometry)[0] * _size(g.geometry)[1], reverse=True)
    for g in groups:
        target = g.windows[0] if getattr(g, 'windows', None) else None
        if target is None or target is win:
            continue
        d = _direction(target, 'auto', cell, deco)
        if d is not None:
            return _launch(boss, win, '--location=' + ('vsplit' if d else 'hsplit'),
                           f'--next-to=id:{target.id}')
    # Plus de place du tout : nouvel onglet, même dossier
    return _launch(boss, win, '--type=tab')


def _resize(boss, win, tab, quality, step):
    if tab is None:
        return
    root = None
    if _layout_name(tab) == 'splits':
        root = getattr(tab.current_layout, 'pairs_root', None)
    saved = [(p, p.bias) for p in root.self_and_descendants()] if root is not None else []
    tab.resize_window(quality, step)
    if saved and not _all_fit(tab, HARD_COLS, HARD_LINES):
        for p, bias in saved:          # on annule : un panneau serait inutilisable
            p.bias = bias
        tab.relayout()


# ------------------------------------------------------------------
#  Kitten
# ------------------------------------------------------------------
def main(args):
    return None


def handle_result(args, answer, target_window_id, boss):
    win = boss.window_id_map.get(target_window_id) or boss.active_window
    tab = (win.tabref() if win is not None else None) or boss.active_tab
    cmd = args[1] if len(args) > 1 else 'split'
    try:
        if cmd == 'resize':
            quality = args[2] if len(args) > 2 else 'wider'
            step = int(args[3]) if len(args) > 3 else 2
            _resize(boss, win, tab, quality, step)
        else:
            _split(boss, win, tab, args[2] if len(args) > 2 else 'auto')
    except Exception as e:
        _log(cmd, 'a échoué :', e)
        if cmd != 'resize':
            _launch(boss, win)        # filet de sécurité : nouvelle fenêtre classique


handle_result.no_ui = True


# ------------------------------------------------------------------
#  Watcher : garde-fou quand la fenêtre kitty elle-même rétrécit
# ------------------------------------------------------------------
_pending = {}
_last_notify = [0.0]


def _need(node, cell, deco, cols, lines):
    """Taille (px) minimale d'un sous-arbre de splits pour que chaque
    panneau garde cols x lines, en tenant compte des proportions."""
    cw, ch = cell
    dx, dy, b = deco
    if node is None:
        return 0, 0
    if not hasattr(node, 'horizontal'):            # feuille = un panneau
        return cols * cw + dx, lines * ch + dy
    one, two = node.one, node.two
    if one is None or two is None:
        return _need(one if two is None else two, cell, deco, cols, lines)
    (w1, h1), (w2, h2) = _need(one, cell, deco, cols, lines), _need(two, cell, deco, cols, lines)
    bias = min(max(float(node.bias), 0.05), 0.95)
    if node.horizontal:
        return max((w1 + b) / bias, (w2 + b) / (1 - bias)), max(h1, h2)
    return max(w1, w2), max((h1 + b) / bias, (h2 + b) / (1 - bias))


def _splits_fit(tab):
    from kitty.fast_data_types import viewport_for_window
    name, win = _enabled(tab, 'splits'), tab.active_window
    if not name or win is None:
        return False
    central = viewport_for_window(tab.os_window_id)[0]
    root = tab.create_layout_object(name).pairs_root
    w, h = _need(root, _cell_size(win), _deco(win),
                 HARD_COLS * RESTORE_MARGIN, HARD_LINES * RESTORE_MARGIN)
    return w <= central.width and h <= central.height


def _notify(tab):
    if not NOTIFY or time.monotonic() - _last_notify[0] < 300:
        return
    _last_notify[0] = time.monotonic()
    import shutil
    import subprocess
    exe = shutil.which('notify-send')
    if not exe:
        return
    n = max(0, len(list(getattr(tab, 'windows', ()))) - 1)
    body = (f'{n} panneau(x) masqué(s) : la fenêtre est trop petite pour tous les afficher.\n'
            'Ils reviennent quand elle s’agrandit (ou ctrl+shift+z).')
    try:
        subprocess.Popen([exe, '-a', 'kitty', '-i', 'kitty', '-t', '5000', 'kitty · zoom automatique', body],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except Exception:
        pass


def _guard(tab):
    name = _layout_name(tab)
    auto = getattr(tab, '_katty_autozoom', None)
    if name == 'splits':
        if auto:
            tab._katty_autozoom = None
        if len(_groups(tab)) < 2 or _all_fit(tab, HARD_COLS, HARD_LINES):
            return
        tab.resize_window('reset', 1)                 # 1) on égalise les tailles
        if _all_fit(tab, HARD_COLS, HARD_LINES):
            return
        stack = _enabled(tab, 'stack')
        if stack:                                     # 2) zoom sur le panneau actif
            tab._katty_autozoom = time.monotonic()
            tab.goto_layout(stack)
            _notify(tab)
    elif name == 'stack' and auto:
        if time.monotonic() - auto > 0.5 and _splits_fit(tab):
            tab._katty_autozoom = None
            tab.goto_layout(_enabled(tab, 'splits'))


def on_resize(boss, window, data):
    tab = window.tabref() if hasattr(window, 'tabref') else None
    if tab is None or tab.id in _pending:
        return
    tid, ref = tab.id, weakref.ref(tab)

    def run(timer_id=None):
        _pending.pop(tid, None)
        t = ref()
        if t is not None:
            try:
                _guard(t)
            except Exception as e:
                _log('garde-fou :', e)

    try:
        from kitty.fast_data_types import add_timer
        _pending[tab.id] = add_timer(run, 0.05, False)
    except Exception:
        run()
__KATTY_PY__
}

write_p10k_zsh() {
  cat > "$1" <<'__P10K_ZSH__'
# ============================================================
#  p10k.zsh — "Katty Noir"  (v3)
#  Prompt épuré sans fond plein, cadre rétro, icônes Nerd Font
#  Install : cp p10k.zsh ~/.p10k.zsh
#  Dans ~/.zshrc : [[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
#  (ne pas relancer `p10k configure`, ça écraserait ce fichier)
#
#  ╭─  ~/dev/projet · ⎇ main +1 !2 ?3 ─────── ✘ 1 · ⏱ 4s · 󰌘 10.10.14.2 · 14:32:07 ─╮
#  ╰─❯
#
#  Responsive : le prompt suit la largeur du panneau. Quand on divise
#  la fenêtre, les éléments secondaires s'effacent un par un (heure,
#  version de Rust, icône, user@host…) au lieu de faire déborder la
#  ligne ; ils reviennent quand le panneau s'élargit. Le chemin est
#  raccourci à 45 % de la largeur. L'IP du VPN et le code d'erreur
#  restent tant qu'il y a la place.
#
#  Une fois la commande lancée, le prompt est réduit à « ╰─❯ commande »
#  (transient prompt) : les anciennes lignes pleine largeur ne restent
#  pas dans l'écran, donc plus de traînées quand on divise un panneau.
# ============================================================

'builtin' 'local' '-a' 'p10k_config_opts'
[[ ! -o 'aliases'         ]] || p10k_config_opts+=('aliases')
[[ ! -o 'sh_glob'         ]] || p10k_config_opts+=('sh_glob')
[[ ! -o 'no_brace_expand' ]] || p10k_config_opts+=('no_brace_expand')
'builtin' 'setopt' 'no_aliases' 'no_sh_glob' 'brace_expand'

() {
  emulate -L zsh -o extended_glob
  unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~POWERLEVEL9K_GITSTATUS_DIR'
  autoload -Uz is-at-least && is-at-least 5.1 || return

  # ----------------------------------------------------------
  #  Palette (assortie à kitty.conf)
  # ----------------------------------------------------------
  local pink='#e01247'
  local pink_hi='#ff2d55'
  local white='#ffffff'
  local fg='#e6e6e6'
  local green='#98c379'
  local yellow='#e5c07b'
  local blue='#82bdf0'
  local magenta='#c678dd'
  local cyan='#56b6c2'
  local grey='#6b7280'
  local dim='#3b3f4a'

  # ----------------------------------------------------------
  #  Éléments
  # ----------------------------------------------------------
  typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
    os_icon
    dir
    vcs
    virtualenv
    newline
    prompt_char
  )

  typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    status
    command_execution_time
    background_jobs
    rust_version
    vpn_ip
    context
    time
  )

  # ----------------------------------------------------------
  #  Responsive : seuils en colonnes du panneau. Sous le seuil,
  #  l'élément est masqué (p10k cache de toute façon la partie
  #  droite entière si elle ne tient pas : ceci évite d'en arriver là)
  # ----------------------------------------------------------
  function p10k-on-pre-prompt() {
    local -i c=${COLUMNS:-80}
    local t=hide r=hide o=hide m=hide
    (( c >= 100 )) && t=show      # heure
    (( c >= 90  )) && r=show      # version de Rust
    (( c >= 70  )) && o=show      # icône de la distro
    (( c >= 60  )) && m=show      # user@host, durée, jobs
    p10k display '1/right/time'=$t '1/right/rust_version'=$r '1/left/os_icon'=$o \
                 '1/right/(context|command_execution_time|background_jobs)'=$m
  }
  # (le recalcul immédiat au redimensionnement, TRAPWINCH, est en bas du
  #  fichier : un trap défini ici disparaîtrait à la fin de ce bloc)

  # ----------------------------------------------------------
  #  Style global : aucun fond, séparateurs discrets
  # ----------------------------------------------------------
  typeset -g POWERLEVEL9K_MODE=nerdfont-v3
  typeset -g POWERLEVEL9K_ICON_PADDING=none
  typeset -g POWERLEVEL9K_BACKGROUND=
  typeset -g POWERLEVEL9K_FOREGROUND=$fg

  typeset -g POWERLEVEL9K_LEFT_SEGMENT_SEPARATOR=''
  typeset -g POWERLEVEL9K_RIGHT_SEGMENT_SEPARATOR=''
  typeset -g POWERLEVEL9K_LEFT_SUBSEGMENT_SEPARATOR="%F{$dim} · "
  typeset -g POWERLEVEL9K_RIGHT_SUBSEGMENT_SEPARATOR="%F{$dim} · "
  typeset -g POWERLEVEL9K_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=' '
  typeset -g POWERLEVEL9K_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_LAST_SEGMENT_END_SYMBOL=' '

  # Cadre arrondi : ligne continue entre la gauche et la droite
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX="%F{$pink}╭─"
  typeset -g POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_PREFIX="%F{$pink}├─"
  typeset -g POWERLEVEL9K_MULTILINE_LAST_PROMPT_PREFIX="%F{$pink}╰─"
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_SUFFIX="%F{$pink}─╮"
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR='─'
  typeset -g POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_FOREGROUND=$dim

  typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true
  typeset -g POWERLEVEL9K_SHOW_RULER=false
  # Anciens prompts réduits à « ╰─❯ commande » : évite les traînées de "─"
  # quand un panneau rétrécit (split) et que kitty re-découpe les vieilles lignes.
  #   same-dir = garde le prompt complet quand tu as changé de dossier
  #   off      = garde tous les prompts complets (heure, git…) dans l'historique
  typeset -g POWERLEVEL9K_TRANSIENT_PROMPT=always
  typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
  typeset -g POWERLEVEL9K_DISABLE_HOT_RELOAD=true

  # ----------------------------------------------------------
  #  Icône de la distro
  # ----------------------------------------------------------
  typeset -g POWERLEVEL9K_OS_ICON_FOREGROUND=$pink
  typeset -g POWERLEVEL9K_OS_ICON_CONTENT_EXPANSION='%B${P9K_CONTENT}%b'

  # ----------------------------------------------------------
  #  Dossier : préfixe estompé, dossier courant en gras blanc
  # ----------------------------------------------------------
  typeset -g POWERLEVEL9K_DIR_FOREGROUND=$blue
  typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND=$grey
  typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND=$white
  typeset -g POWERLEVEL9K_DIR_ANCHOR_BOLD=true
  typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_unique
  typeset -g POWERLEVEL9K_SHORTEN_DELIMITER=''
  typeset -g POWERLEVEL9K_SHORTEN_DIR_LENGTH=1
  # Le chemin s'adapte à la largeur du panneau (45 % de la largeur du terminal)
  typeset -g POWERLEVEL9K_DIR_MAX_LENGTH='45%'
  # Les "/" étaient en #3b3f4a sur fond noir : quasi invisibles (« a b c » au lieu de « a/b/c »)
  typeset -g POWERLEVEL9K_DIR_PATH_SEPARATOR="%F{$grey}/%F{$blue}"
  typeset -g POWERLEVEL9K_DIR_VISUAL_IDENTIFIER_COLOR=$pink

  typeset -g POWERLEVEL9K_DIR_DEFAULT_VISUAL_IDENTIFIER_EXPANSION=$'\uF07B'
  typeset -g POWERLEVEL9K_DIR_HOME_VISUAL_IDENTIFIER_EXPANSION=$'\uF015'
  typeset -g POWERLEVEL9K_DIR_HOME_SUBFOLDER_VISUAL_IDENTIFIER_EXPANSION=$'\uF07C'
  typeset -g POWERLEVEL9K_DIR_ETC_VISUAL_IDENTIFIER_EXPANSION=$'\uF013'
  typeset -g POWERLEVEL9K_DIR_NOT_WRITABLE_VISUAL_IDENTIFIER_EXPANSION=$'\uF023'
  typeset -g POWERLEVEL9K_DIR_NOT_WRITABLE_FOREGROUND=$yellow

  # ----------------------------------------------------------
  #  Git : branche + compteurs, couleur selon l'état du dépôt
  # ----------------------------------------------------------
  function my_git_formatter() {
    emulate -L zsh

    if [[ -n $P9K_CONTENT ]]; then
      typeset -g my_git_format=$P9K_CONTENT
      return
    fi

    local clean='%F{#98c379}'
    local modified='%F{#e5c07b}'
    local untracked='%F{#61afef}'
    local conflicted='%F{#ff2d55}'
    local meta='%F{#6b7280}'

    local state
    if (( $1 )); then
      state=$clean
      (( VCS_STATUS_HAS_CONFLICTED )) && state=$conflicted
      (( ! VCS_STATUS_HAS_CONFLICTED && (VCS_STATUS_HAS_STAGED || VCS_STATUS_HAS_UNSTAGED) )) && state=$modified
      (( ! VCS_STATUS_HAS_CONFLICTED && ! VCS_STATUS_HAS_STAGED && ! VCS_STATUS_HAS_UNSTAGED && VCS_STATUS_HAS_UNTRACKED )) && state=$untracked
    else
      # Chargement en cours : tout en gris
      state=$meta
      clean=$meta modified=$meta untracked=$meta conflicted=$meta
    fi

    local where
    if [[ -n $VCS_STATUS_LOCAL_BRANCH ]]; then
      where=${(V)VCS_STATUS_LOCAL_BRANCH}
    elif [[ -n $VCS_STATUS_TAG ]]; then
      where="#${(V)VCS_STATUS_TAG}"
    else
      where="@${VCS_STATUS_COMMIT[1,8]}"
    fi
    (( $#where > 32 )) && where[13,-13]="…"

    local res="${state}"$'\uE0A0'" ${where//\%/%%}"
    (( VCS_STATUS_COMMITS_BEHIND  )) && res+=" ${clean}⇣${VCS_STATUS_COMMITS_BEHIND}"
    (( VCS_STATUS_COMMITS_AHEAD   )) && res+=" ${clean}⇡${VCS_STATUS_COMMITS_AHEAD}"
    (( VCS_STATUS_STASHES         )) && res+=" ${clean}*${VCS_STATUS_STASHES}"
    (( VCS_STATUS_NUM_CONFLICTED  )) && res+=" ${conflicted}~${VCS_STATUS_NUM_CONFLICTED}"
    (( VCS_STATUS_NUM_STAGED      )) && res+=" ${modified}+${VCS_STATUS_NUM_STAGED}"
    (( VCS_STATUS_NUM_UNSTAGED    )) && res+=" ${modified}!${VCS_STATUS_NUM_UNSTAGED}"
    (( VCS_STATUS_NUM_UNTRACKED   )) && res+=" ${untracked}?${VCS_STATUS_NUM_UNTRACKED}"

    typeset -g my_git_format=$res
  }
  functions -M my_git_formatter 2>/dev/null

  typeset -g POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY=-1
  typeset -g POWERLEVEL9K_VCS_DISABLE_GITSTATUS_FORMATTING=true
  typeset -g POWERLEVEL9K_VCS_CONTENT_EXPANSION='${$((my_git_formatter(1)))+${my_git_format}}'
  typeset -g POWERLEVEL9K_VCS_LOADING_CONTENT_EXPANSION='${$((my_git_formatter(0)))+${my_git_format}}'
  typeset -g POWERLEVEL9K_VCS_{CLEAN,UNTRACKED,MODIFIED}_CONTENT_EXPANSION='${$((my_git_formatter(1)))+${my_git_format}}'
  typeset -g POWERLEVEL9K_VCS_{PREFIX,SUFFIX}=''
  typeset -g POWERLEVEL9K_VCS_VISUAL_IDENTIFIER_EXPANSION=''
  typeset -g POWERLEVEL9K_VCS_BACKENDS=(git)

  # ----------------------------------------------------------
  #  Environnement virtuel Python
  # ----------------------------------------------------------
  typeset -g POWERLEVEL9K_VIRTUALENV_FOREGROUND=$yellow
  typeset -g POWERLEVEL9K_VIRTUALENV_SHOW_PYTHON_VERSION=false
  typeset -g POWERLEVEL9K_VIRTUALENV_LEFT_DELIMITER='('
  typeset -g POWERLEVEL9K_VIRTUALENV_RIGHT_DELIMITER=')'
  typeset -g POWERLEVEL9K_VIRTUALENV_VISUAL_IDENTIFIER_EXPANSION=$'\uE73C'

  # ----------------------------------------------------------
  #  Version de Rust : seulement dans un projet Cargo
  # ----------------------------------------------------------
  typeset -g POWERLEVEL9K_RUST_VERSION_PROJECT_ONLY=true
  typeset -g POWERLEVEL9K_RUST_VERSION_FOREGROUND='#dea584'
  typeset -g POWERLEVEL9K_RUST_VERSION_VISUAL_IDENTIFIER_EXPANSION=$'\uE7A8'

  # ----------------------------------------------------------
  #  Caractère de prompt
  # ----------------------------------------------------------
  typeset -g POWERLEVEL9K_PROMPT_CHAR_BACKGROUND=
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=$pink
  typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=$yellow
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIINS_CONTENT_EXPANSION='❯'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VICMD_CONTENT_EXPANSION='❮'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIVIS_CONTENT_EXPANSION='▣'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIOWR_CONTENT_EXPANSION='▷'
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OVERWRITE_STATE=true
  typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=''

  # ----------------------------------------------------------
  #  Code de retour de la dernière commande
  # ----------------------------------------------------------
  typeset -g POWERLEVEL9K_STATUS_EXTENDED_STATES=true
  typeset -g POWERLEVEL9K_STATUS_OK=false
  typeset -g POWERLEVEL9K_STATUS_OK_PIPE=false
  typeset -g POWERLEVEL9K_STATUS_ERROR=true
  typeset -g POWERLEVEL9K_STATUS_ERROR_FOREGROUND=$pink_hi
  typeset -g POWERLEVEL9K_STATUS_ERROR_VISUAL_IDENTIFIER_EXPANSION='✘'
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL=true
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_FOREGROUND=$pink_hi
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_VISUAL_IDENTIFIER_EXPANSION='☠'
  typeset -g POWERLEVEL9K_STATUS_ERROR_PIPE_FOREGROUND=$pink_hi

  # ----------------------------------------------------------
  #  Durée d'exécution
  # ----------------------------------------------------------
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=0
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FORMAT='d h m s'
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=$yellow
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_VISUAL_IDENTIFIER_EXPANSION=$'\uF252'

  # ----------------------------------------------------------
  #  Jobs en arrière-plan
  # ----------------------------------------------------------
  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_VERBOSE=false
  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_FOREGROUND=$cyan
  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_VISUAL_IDENTIFIER_EXPANSION=$'\uF013'

  # ----------------------------------------------------------
  #  IP du tunnel VPN (tun0 HTB/OpenVPN, wg0, tailscale…) quand il est actif
  #  = ton LHOST, toujours sous les yeux (commande `lhost` pour la copier)
  # ----------------------------------------------------------
  typeset -g POWERLEVEL9K_VPN_IP_INTERFACES='(gpd|wg|(.*tun)|tailscale)[0-9]*|(zt.*)'
  typeset -g POWERLEVEL9K_VPN_IP_SHOW_ALL=false
  typeset -g POWERLEVEL9K_VPN_IP_FOREGROUND=$green
  typeset -g POWERLEVEL9K_VPN_IP_VISUAL_IDENTIFIER_EXPANSION=$'\uF023'

  # ----------------------------------------------------------
  #  Contexte user@host (uniquement root ou SSH)
  # ----------------------------------------------------------
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_FOREGROUND=$pink_hi
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_TEMPLATE='%B%n@%m%b'
  typeset -g POWERLEVEL9K_CONTEXT_{REMOTE,REMOTE_SUDO}_FOREGROUND=$magenta
  typeset -g POWERLEVEL9K_CONTEXT_{REMOTE,REMOTE_SUDO}_TEMPLATE='%n@%m'
  typeset -g POWERLEVEL9K_CONTEXT_{DEFAULT,SUDO}_CONTENT_EXPANSION=
  typeset -g POWERLEVEL9K_CONTEXT_VISUAL_IDENTIFIER_EXPANSION=''

  # ----------------------------------------------------------
  #  Horloge
  # ----------------------------------------------------------
  typeset -g POWERLEVEL9K_TIME_FOREGROUND=$grey
  typeset -g POWERLEVEL9K_TIME_FORMAT='%D{%H:%M:%S}'
  typeset -g POWERLEVEL9K_TIME_UPDATE_ON_COMMAND=false
  typeset -g POWERLEVEL9K_TIME_VISUAL_IDENTIFIER_EXPANSION=$'\uF017'

  (( ! $+functions[p10k] )) || p10k reload
}

typeset -g POWERLEVEL9K_CONFIG_FILE=${${(%):-%x}:a}

# Redimensionnement (split, zoom, fenêtre) : le prompt affiché est adapté
# à la nouvelle largeur tout de suite, sans attendre la commande suivante
function TRAPWINCH() {
  (( $+functions[p10k-on-pre-prompt] && $+functions[p10k] )) && p10k-on-pre-prompt
  return 0
}

(( ${#p10k_config_opts} )) && setopt ${p10k_config_opts[@]}
'builtin' 'unset' 'p10k_config_opts'
__P10K_ZSH__
}

write_zshrc() {
  cat > "$1" <<'__ZSHRC__'
# ============================================================
#  ~/.zshrc — Katty Noir  (v3)
#  Tes ajouts perso : ~/.zshrc.local (chargé à la fin, jamais écrasé)
#  Aide-mémoire des raccourcis : tape `katty`
#
#  Optimisé pour démarrer vite : rien n'est lancé en sous-processus à
#  l'ouverture d'un shell (init de fzf/zoxide/dircolors en cache, base de
#  complétion reconstruite une fois par jour, plugins précompilés).
# ============================================================

# Instant prompt de Powerlevel10k : le prompt s'affiche tout de suite et
# le reste se charge derrière. Doit rester tout en haut ; tout ce qui
# demande une saisie (mot de passe, [o/n]…) doit être placé au-dessus.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

ZSH_DIR=$HOME/.zsh
ZSH_CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/zsh
[[ -d $ZSH_CACHE ]] || mkdir -p -- $ZSH_CACHE
zmodload -F zsh/stat b:zstat 2>/dev/null

# PATH sans doublons (même après plusieurs `exec zsh`) ; les dossiers
# absents sont ignorés (Rust, Go… apparaissent dès qu'ils sont installés)
typeset -U path fpath
path=($HOME/.local/bin(N-/) $HOME/.cargo/bin(N-/) $HOME/go/bin(N-/) $path)

# ---- Historique ------------------------------------------------
HISTFILE=${HISTFILE:-$HOME/.zsh_history}
HISTSIZE=100000
SAVEHIST=100000
setopt EXTENDED_HISTORY SHARE_HISTORY HIST_FCNTL_LOCK HIST_VERIFY
setopt HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS HIST_EXPIRE_DUPS_FIRST

# ---- Options ---------------------------------------------------
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT
setopt INTERACTIVE_COMMENTS NO_BEEP NO_FLOW_CONTROL NUMERIC_GLOB_SORT
setopt COMPLETE_IN_WORD ALWAYS_TO_END
DIRSTACKSIZE=20
WORDCHARS=${WORDCHARS//[\/.=]}   # ctrl+w / ctrl+flèches s'arrêtent aux / . =
# Raccourcis façon emacs (ceux de ce fichier), même si $EDITOR est vim.
# Pour le mode vi : `bindkey -v` dans ~/.zshrc.local
bindkey -e

# _nf_cached <nom> <commande…> : sortie d'une commande d'init mise en
# cache dans $ZSH_CACHE (chemin renvoyé dans $REPLY). Régénérée seulement
# quand le binaire change (mise à jour) ; un échec est mémorisé aussi.
_nf_cached() {
  local bin=${commands[$2]} out=$ZSH_CACHE/init-$1.zsh line stamp
  local -a st
  REPLY=
  [[ -n $bin ]] || return 1
  zstat -A st +mtime -- $bin 2>/dev/null || st=(0)
  stamp="# $bin $st[1] $ZSH_VERSION"
  [[ -r $out ]] && IFS= read -r line < $out
  if [[ $line != $stamp ]]; then
    if ! { print -r -- $stamp; "${@:2}" } >| $out.$$ 2>/dev/null; then
      print -r -- $stamp$'\nreturn 1' >| $out.$$
    fi
    command mv -f -- $out.$$ $out 2>/dev/null || { command rm -f -- $out.$$; return 1 }
  fi
  REPLY=$out
}

# Couleurs de `ls` et de la complétion (dircolors, en cache)
if [[ -z $LS_COLORS ]] && _nf_cached dircolors dircolors -b; then
  source $REPLY
fi

# ---- Complétion ------------------------------------------------
fpath=($ZSH_DIR/plugins/zsh-completions/src(N-/) $fpath)
autoload -Uz compinit
() {
  local dump=$ZSH_CACHE/zcompdump-$ZSH_VERSION
  local -a fresh=($dump(N.mh-20))
  if (( $#fresh )); then
    compinit -C -d $dump            # base de moins de 20 h : chargement direct
  else
    compinit -i -d $dump            # sinon on la reconstruit (et on la précompile)
    zcompile -- $dump 2>/dev/null
  fi
}

zstyle ':completion:*' menu no                    # fzf-tab prend le relais
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path $ZSH_CACHE/compcache
zstyle ':completion:*' squeeze-slashes true
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':completion:*:*:*:*:processes' command 'ps -u $USER -o pid,user,comm -w -w'

# ---- Thème -----------------------------------------------------
if [[ -r $ZSH_DIR/powerlevel10k/powerlevel10k.zsh-theme ]]; then
  source $ZSH_DIR/powerlevel10k/powerlevel10k.zsh-theme
  [[ -r ~/.p10k.zsh ]] && source ~/.p10k.zsh
fi

# ---- Environnement ---------------------------------------------
if [[ -z $EDITOR ]]; then
  for _nf_e in nvim vim nano vi; do
    (( $+commands[$_nf_e] )) && { export EDITOR=$_nf_e VISUAL=$_nf_e; break }
  done
  unset _nf_e
fi
export LESS='-R -F -i -M'
export BAT_THEME=TwoDark
# Pages de manuel en couleur (palette Katty)
export LESS_TERMCAP_md=$'\e[1;38;2;224;18;71m'                      # titres, gras
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_us=$'\e[4;38;2;97;175;239m'                     # arguments, souligné
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;38;2;0;0;0;48;2;229;192;123m'         # recherche, barre d'état
export LESS_TERMCAP_se=$'\e[0m'
export GROFF_NO_SGR=1

# ---- fzf (couleurs Katty) ------------------------------------
export FZF_DEFAULT_OPTS="--height=40% --layout=reverse --border=rounded --info=inline \
--prompt='❯ ' --pointer='▌' --marker='✚' \
--color=bg+:#1a1a1a,fg:#e6e6e6,fg+:#ffffff,hl:#e01247,hl+:#ff2d55,pointer:#e01247 \
--color=prompt:#e01247,info:#6b7280,border:#3b3f4a,marker:#98c379,spinner:#e01247,header:#56b6c2 \
--bind=ctrl-/:toggle-preview"

if (( $+commands[fd] )); then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND='fd --hidden --follow --exclude .git'
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi
# Aperçu : contenu des fichiers (bat), contenu des dossiers (eza)
_nf_preview='if [ -d {} ]; then eza -1 --color=always --icons=always -- {} 2>/dev/null || ls -1 --color=always -- {}; else bat --color=always --style=numbers --line-range=:300 -- {} 2>/dev/null || head -n 300 -- {}; fi'
export FZF_CTRL_T_OPTS="--preview '$_nf_preview'"
export FZF_ALT_C_OPTS="--preview '$_nf_preview'"
export FZF_CTRL_R_OPTS="--preview 'echo {}' --preview-window=down:3:hidden:wrap"
unset _nf_preview

# ctrl+r (historique), ctrl+t (fichiers), alt+c (dossiers) ; fzf ≥ 0.48
# en cache, sinon les scripts fournis par la distribution
_nf_fzf_modern=0
if (( $+commands[fzf] )); then
  if _nf_cached fzf fzf --zsh && source $REPLY; then
    _nf_fzf_modern=1
  else
    for _nf_f in /usr/share/fzf/shell/key-bindings.zsh \
                 /usr/share/fzf/key-bindings.zsh \
                 /usr/share/doc/fzf/examples/key-bindings.zsh; do
      [[ -r $_nf_f ]] && { source $_nf_f; break }
    done
    unset _nf_f
  fi
fi

# ---- Plugins ---------------------------------------------------
# Ordre : fzf-tab (après compinit) → widgets perso → autosuggestions →
# syntax-highlighting → history-substring-search (doit être le dernier)
if (( $+commands[fzf] )) && [[ -r $ZSH_DIR/plugins/fzf-tab/fzf-tab.plugin.zsh ]]; then
  source $ZSH_DIR/plugins/fzf-tab/fzf-tab.plugin.zsh
  zstyle ':fzf-tab:*' use-fzf-default-opts yes    # couleurs de FZF_DEFAULT_OPTS
  zstyle ':fzf-tab:*' switch-group '<' '>'         # < et > : groupe de résultats précédent / suivant
  # Aperçus pendant la complétion (tab)
  zstyle ':fzf-tab:complete:(cd|z|zi|pushd|eza|ls|rmdir):*' fzf-preview \
    'eza -1 --color=always --icons=always -- $realpath 2>/dev/null || ls -1 --color=always -- $realpath'
  zstyle ':fzf-tab:complete:(cat|bat|less|more|head|tail|nano|vi|vim|nvim|code|cp|mv|rm|file|strings|xxd|chmod|source):*' fzf-preview \
    'if [[ -d $realpath ]]; then eza -1 --color=always --icons=always -- $realpath 2>/dev/null || ls -1 --color=always -- $realpath; else bat --color=always --style=numbers --line-range=:200 -- $realpath 2>/dev/null || head -n 200 -- $realpath; fi'
  zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-preview \
    '[[ $group == "[process ID]" ]] && ps -p $word -o cmd= -w -w'
  zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-flags --preview-window=down:3:wrap
  zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview 'SYSTEMD_COLORS=1 systemctl status -- $word'
  zstyle ':fzf-tab:complete:(-parameter-|-brace-parameter-|export|unset):*' fzf-preview 'echo ${(P)word}'
  zstyle ':fzf-tab:complete:git-(add|diff|restore):*' fzf-preview 'git diff --color=always -- $word'
  zstyle ':fzf-tab:complete:git-log:*' fzf-preview 'git log --color=always --oneline --graph -20 $word'
else
  zstyle ':completion:*' menu select
fi

# ctrl+g puis ctrl+f/b/t/h/s… : fichiers, branches, tags, commits, stashes git
if (( _nf_fzf_modern )) && [[ -r $ZSH_DIR/plugins/fzf-git/fzf-git.sh ]]; then
  source $ZSH_DIR/plugins/fzf-git/fzf-git.sh
fi

# zoxide : `z dossier` saute au dossier le plus fréquenté qui correspond
if _nf_cached zoxide zoxide init zsh; then source $REPLY; fi

# Une URL collée est automatiquement mise entre guillemets (? & # sans danger)
autoload -Uz bracketed-paste-url-magic edit-command-line
zle -N bracketed-paste bracketed-paste-url-magic
zle -N edit-command-line

# Échap Échap : ajoute / retire `sudo` devant la ligne (ou la commande précédente)
_nf_sudo() {
  [[ -z $BUFFER ]] && zle .up-history
  if [[ $BUFFER == sudo\ * ]]; then
    BUFFER=${BUFFER#sudo }
    (( CURSOR = CURSOR > 5 ? CURSOR - 5 : 0 ))
  else
    BUFFER="sudo $BUFFER"
    (( CURSOR += 5 ))
  fi
}
zle -N _nf_sudo

# ctrl+z : ligne vide → reprend le programme suspendu (aller-retour vim/shell) ;
# ligne en cours → la met de côté, elle revient après la commande suivante
_nf_ctrl_z() {
  if [[ -z $BUFFER ]]; then
    (( ${#jobstates} )) || return 0
    BUFFER=' fg'                          # espace devant : pas gardé dans l'historique
    zle .accept-line
  else
    zle .push-input
  fi
}
zle -N _nf_ctrl_z

ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=100      # pas de suggestion pour les gros collages
ZSH_AUTOSUGGEST_MANUAL_REBIND=1          # widgets liés une seule fois : prompt plus rapide
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6b7280'
[[ -r $ZSH_DIR/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] &&
  source $ZSH_DIR/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)
ZSH_HIGHLIGHT_MAXLENGTH=300              # pas de coloration sur les lignes énormes
if [[ -r $ZSH_DIR/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
source $ZSH_DIR/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
ZSH_HIGHLIGHT_STYLES[command]='fg=#98c379'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#98c379'
ZSH_HIGHLIGHT_STYLES[function]='fg=#98c379'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#98c379,italic'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#56b6c2'
ZSH_HIGHLIGHT_STYLES[suffix-alias]='fg=#56b6c2,underline'
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#e01247,bold'
ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=#e01247'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#ff2d55,bold'
ZSH_HIGHLIGHT_STYLES[path]='fg=#e6e6e6,underline'
ZSH_HIGHLIGHT_STYLES[globbing]='fg=#c678dd'
ZSH_HIGHLIGHT_STYLES[history-expansion]='fg=#c678dd'
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#82bdf0'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#82bdf0'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#e5c07b'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#e5c07b'
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=#e5c07b'
ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]='fg=#56b6c2'
ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]='fg=#56b6c2'
ZSH_HIGHLIGHT_STYLES[redirection]='fg=#c678dd'
ZSH_HIGHLIGHT_STYLES[comment]='fg=#6b7280,italic'
fi

HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND='bg=#e01247,fg=#ffffff,bold'
HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND='bg=#ff2d55,fg=#ffffff,bold'
HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE=1
if [[ -r $ZSH_DIR/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]]; then
  source $ZSH_DIR/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
  bindkey '^[[A' history-substring-search-up       # ↑ / ↓ : historique filtré par
  bindkey '^[[B' history-substring-search-down     # ce qui est déjà tapé
  bindkey '^[OA' history-substring-search-up
  bindkey '^[OB' history-substring-search-down
fi

# ---- Raccourcis clavier ----------------------------------------
bindkey '^[[1;5C' forward-word                     # ctrl+→
bindkey '^[[1;5D' backward-word                    # ctrl+←
bindkey '^[[H'    beginning-of-line                # Début
bindkey '^[OH'    beginning-of-line
bindkey '^[[F'    end-of-line                      # Fin
bindkey '^[OF'    end-of-line
bindkey '^[[3~'   delete-char                      # Suppr
bindkey '^[[3;5~' kill-word                        # ctrl+Suppr
bindkey '^H'      backward-kill-word               # ctrl+Retour arrière
bindkey '^ '      autosuggest-accept               # ctrl+espace : accepte la suggestion
bindkey '^X^E'    edit-command-line                # ctrl+x ctrl+e : ligne dans $EDITOR
bindkey '^[^['    _nf_sudo                         # Échap Échap : sudo
bindkey '^Z'      _nf_ctrl_z                       # ctrl+z : fg / mettre la ligne de côté

# Commande introuvable → paquet qui la fournit (Ubuntu/Debian, Arch avec pkgfile)
for _nf_f in /etc/zsh_command_not_found /usr/share/doc/pkgfile/command-not-found.zsh; do
  [[ -r $_nf_f ]] && { source $_nf_f; break }
done
unset _nf_f

# ---- Alias -----------------------------------------------------
if (( $+commands[eza] )); then
  alias ls='eza --icons=auto --group-directories-first'
  alias ll='eza -l --icons=auto --group-directories-first --git'
  alias la='eza -la --icons=auto --group-directories-first --git'
  alias lt='eza --tree --level=2 --icons=auto --group-directories-first'
else
  alias ls='ls --color=auto --group-directories-first'
  alias ll='ls -lh'
  alias la='ls -lAh'
fi
alias l='ll'
(( $+commands[batcat] && ! $+commands[bat] )) && alias bat='batcat'
(( $+commands[fdfind] && ! $+commands[fd] )) && alias fd='fdfind'
alias grep='grep --color=auto'
alias diff='diff --color=auto'
# -c=auto : couleurs seulement dans un terminal (avec -c seul, `ip a | grep tun0` recevait des codes couleur)
alias ip='ip -c=auto'
alias ips='ip -br -c=auto addr'          # toutes les IP, une ligne par interface
alias ports='ss -tulpn'
alias df='df -h'
alias free='free -h'
alias mkdir='mkdir -p'
alias path='print -l $path'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
if (( $+commands[kitten] )); then
  alias icat='kitten icat'               # afficher une image dans le terminal
  alias kdiff='kitten diff'              # diff côte à côte (images comprises)
fi

# ---- Fonctions -------------------------------------------------
reload() {                                # recharge le shell en vidant les caches
  command rm -f -- $ZSH_CACHE/init-*.zsh(N) $ZSH_CACHE/zcompdump-*(N)
  exec zsh
}
mkcd() { mkdir -p -- "$1" && cd -- "$1" }                      # crée un dossier et y entre
bak()  { local f; for f in "$@"; do command cp -a -- "$f" "$f.bak-$(date +%Y%m%d-%H%M%S)"; done }

_nf_vpn_ip() {
  command ip -4 -o addr show 2>/dev/null |
    awk '$2 ~ /^(tun|wg|tailscale)/ { split($4, a, "/"); print a[1]; exit }'
}
lhost() {                                 # IP du tunnel VPN (tun0/wg0…), copiée dans le presse-papier
  local vpn_ip=$(_nf_vpn_ip)
  if [[ -z $vpn_ip ]]; then print -u2 "Aucun tunnel VPN actif."; return 1; fi
  print -r -- $vpn_ip
  (( $+commands[kitten] )) && print -rn -- $vpn_ip | kitten clipboard 2>/dev/null
  return 0
}
serve() {                                 # sert le dossier courant en HTTP (port 8000 par défaut)
  local port=${1:-8000} vpn_ip=$(_nf_vpn_ip)
  [[ -n $vpn_ip ]] && print -P "%F{#98c379}➜%f  http://$vpn_ip:$port/  %F{#6b7280}(VPN)%f"
  python3 -m http.server $port
}

x() {                                     # x <archive>… : extrait n'importe quelle archive
  local f
  for f in "$@"; do
    if [[ ! -f $f ]]; then print -u2 "x : $f introuvable"; continue; fi
    case ${f:l} in
      *.tar.gz|*.tgz)        tar -xzf $f ;;
      *.tar.bz2|*.tbz2|*.tbz) tar -xjf $f ;;
      *.tar.xz|*.txz)        tar -xJf $f ;;
      *.tar.zst|*.tzst)      tar --zstd -xf $f ;;
      *.tar)                 tar -xf $f ;;
      *.gz)                  gunzip -k -- $f ;;
      *.bz2)                 bunzip2 -k -- $f ;;
      *.xz)                  unxz -k -- $f ;;
      *.zst)                 unzstd -- $f ;;
      *.zip|*.jar|*.apk|*.whl|*.war) unzip -- $f ;;
      *.7z)                  7z x -- $f ;;
      *.rar)                 unrar x -- $f 2>/dev/null || 7z x -- $f ;;
      *.deb)                 ar x -- $f ;;
      *.rpm)                 rpm2cpio $f | cpio -idmv ;;
      *)                     print -u2 "x : format non reconnu : $f"; return 1 ;;
    esac
  done
}

if (( $+commands[fzf] )); then
  fkill() {                               # tuer un ou plusieurs processus choisis avec fzf
    local pids
    pids=$(ps -u $USER -o pid=,etime=,cmd= | fzf -m --header='Tab : sélection multiple' | awk '{print $1}')
    [[ -n $pids ]] && kill -${1:-15} ${(f)pids}
  }
  fe() {                                  # ouvrir un fichier choisi avec fzf dans l'éditeur
    local f
    f=$(fzf --query="$*" --preview 'bat --color=always --style=numbers --line-range=:300 -- {} 2>/dev/null || head -300 -- {}') &&
      ${EDITOR:-vi} -- $f
  }
fi
if (( _nf_fzf_modern && $+commands[rg] )); then
  frg() {                                 # recherche dans le CONTENU des fichiers, en direct
    local rg='rg --column --line-number --no-heading --color=always --smart-case'
    fzf --ansi --disabled --query="$*" --delimiter=: \
        --bind="start:reload:[ -n {q} ] && $rg -- {q} || true" \
        --bind="change:reload:sleep 0.1; [ -n {q} ] && $rg -- {q} || true" \
        --preview='bat --color=always --highlight-line={2} -- {1} 2>/dev/null' \
        --preview-window='up,60%,border-bottom,+{2}+3/3,~3' \
        --bind="enter:become(${EDITOR:-vi} +{2} {1})"
  }
fi

katty() {                               # aide-mémoire
  local p=$'\e[1;38;2;224;18;71m' k=$'\e[38;2;229;192;123m' d=$'\e[38;2;107;114;128m' r=$'\e[0m'
  print -r -- "
${p}Panneaux kitty${r}  ${d}(jamais sous 30×7 : sans place → nouvel onglet ; fenêtre trop petite → zoom auto)${r}
  ${k}ctrl+shift+entrée${r}    nouveau panneau (coupe le côté le plus long)
  ${k}ctrl+shift+l / d${r}     nouveau panneau à droite / en dessous
  ${k}ctrl+alt+h/j/k/l${r}     aller au panneau gauche / bas / haut / droite
  ${k}ctrl+alt+maj+h/j/k/l${r} redimensionner
  ${k}ctrl+shift+z${r}         zoom (aller-retour)       ${k}ctrl+shift+o${r}  pivoter
  ${k}ctrl+shift+b${r}         rééquilibrer              ${k}ctrl+shift+w${r}  fermer
${p}Onglets & recherche${r}
  ${k}ctrl+shift+t${r}         nouvel onglet             ${k}alt+1…9${r}       aller à l'onglet n
  ${k}ctrl+shift+f${r}         chercher dans l'historique du terminal
  ${k}ctrl+shift+↑ / ↓${r}     prompt précédent / suivant
  ${k}ctrl+shift+g${r}         sortie de la dernière commande
  ${k}ctrl+shift+m${r}         surligner flags CTF / IP / erreurs
  ${k}ctrl+shift+e${r}         ouvrir une URL affichée   ${k}ctrl+shift+p f${r} insérer un chemin affiché
${p}Shell${r}
  ${k}tab${r}                  complétion fzf avec aperçu (${k}<${r} / ${k}>${r} : changer de groupe)
  ${k}ctrl+r${r} / ${k}ctrl+t${r} / ${k}alt+c${r}  historique / fichiers / dossiers avec fzf
  ${k}ctrl+g ctrl+f/b/h/s${r}  git : fichiers, branches, commits, stashes (${k}ctrl+g ?${r} : tout)
  ${k}↑ / ↓${r}                historique filtré par le début de la ligne
  ${k}ctrl+espace${r}          accepter la suggestion grise
  ${k}Échap Échap${r}          ajouter / retirer sudo
  ${k}ctrl+z${r}               ligne vide : revenir au programme suspendu
  ${k}ctrl+x ctrl+e${r}        éditer la ligne dans \$EDITOR
${p}Commandes${r}
  ${k}z${r} dossier   ${k}x${r} archive   ${k}fe${r} [motif]   ${k}frg${r} [texte]   ${k}fkill${r}   ${k}mkcd${r}   ${k}bak${r} fichier
  ${k}lhost${r} (IP du VPN)   ${k}serve${r} [port]   ${k}ips${r}   ${k}ports${r}   ${k}icat${r} image   ${k}reload${r}
  ${d}Tes ajouts perso : ~/.zshrc.local${r}
"
}

if [[ -r ~/.zshrc.local ]]; then source ~/.zshrc.local; fi
__ZSHRC__
}

# Adapte kitty.conf à la version de kitty installée : une option ou une
# action inconnue de cette version est mise en commentaire (sinon kitty
# ouvrirait une fenêtre d'erreur à chaque démarrage). Utilise le propre
# analyseur de kitty, donc toujours juste, quelle que soit la version.
KITTY_ADAPT_PY=$(cat <<'__PY__'
import sys
path = sys.argv[-1]
try:
    from kitty.config import load_config
    from kitty.constants import str_version
    bad = []
    load_config(path, accumulate_bad_lines=bad)
except Exception:
    raise SystemExit(0)
numbers = {b.number for b in bad}
try:
    from kitty.actions import get_all_actions
    actions = {a.name for group in get_all_actions().values() for a in group}
except Exception:
    actions = set()
try:
    from kitty.options.types import option_names
    known = set(option_names)
except Exception:
    known = set()
with open(path, encoding='utf-8') as f:
    lines = f.read().split('\n')
out, off = [], []
for n, line in enumerate(lines, 1):
    words = line.split()
    disable = n in numbers
    if not disable and known and words and not words[0].startswith('#'):
        disable = words[0] not in known       # option inconnue de cette version
    if not disable and actions and words[:1] == ['map'] and len(words) > 2 \
            and not any(w.startswith('--') for w in words[1:3]):
        disable = words[2] not in actions     # action inconnue de cette version
    if disable:
        out.append('# [ignoré par kitty %s] %s' % (str_version, line))
        off.append(' '.join(words[:2]))
        if 'search_scrollback' in words:
            out.append('map ctrl+shift+f              show_scrollback')
    else:
        out.append(line)
if off:
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out))
    print('\n'.join(off))
__PY__
)

KITTY_DISABLED=""
adapt_kitty_conf() {  # adapt_kitty_conf <fichier>
  have kitty || return 0
  KITTY_DISABLED=$(kitty +runpy "$KITTY_ADAPT_PY" "$1" 2>>"$LOG") || KITTY_DISABLED=""
}

# Lignes « perso » d'un ancien .zshrc qui n'ont pas d'équivalent dans le
# nouveau (alias, variables, PATH, source, eval, fonctions) : affichées pour
# que rien ne se perde. Le reste (setopt, bindkey, zstyle, if/fi…) est ignoré.
custom_zshrc_lines() {  # custom_zshrc_lines <ancien> <nouveau>
  local code="$WORKDIR/zshrc.code" line l key esc item tail all
  local -a items
  grep -v '^[[:space:]]*#' "$2" > "$code" || true      # le nouveau, sans les commentaires
  sed -e ':a' -e '/\\$/{N;s/\\\n//;ba' -e '}' "$1" | while IFS= read -r line; do
    l=${line#"${line%%[![:space:]]*}"}
    [[ -z $l || $l == '#'* ]] && continue
    if [[ $l =~ (^|[[:space:]\;\&\|])alias[[:space:]]+(-g[[:space:]]+)?([^=[:space:]]+)= ]] ||
       [[ $l =~ ^(function[[:space:]]+)?()([A-Za-z_][A-Za-z0-9_.-]*)[[:space:]]*\(\) ]]; then
      esc=$(sed 's/[][\.*^$+?(){}|/]/\\&/g' <<<"${BASH_REMATCH[3]}")
      grep -qE "alias[[:space:]]+(-g[[:space:]]+)?$esc=|(^|[[:space:];&|{])$esc[[:space:]]*\(\)" "$code" && continue
    elif [[ $l =~ ^(export[[:space:]]+)?(PATH|path)\+?= ]]; then
      all=1
      read -r -a items <<<"$(sed -e 's/^[^=]*=//' -e 's/[()"'\'']//g' -e 's/:/ /g' <<<"$l")"
      for item in "${items[@]}"; do
        [[ $item == '$PATH' || $item == '${PATH}' || $item == '$path' || $item == '$path[@]' ]] && continue
        tail=${item#\$HOME}; tail=${tail#\$\{HOME\}}; tail=${tail#\~}; tail=${tail%/}
        grep -qF -- "$tail" "$code" || all=0
      done
      (( all )) && continue
    elif [[ $l =~ ^(export[[:space:]]+|typeset[[:space:]]+-g[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)\+?= ]]; then
      grep -qE "(^|[^A-Za-z0-9_])${BASH_REMATCH[2]}\+?=" "$code" && continue
    elif [[ $l =~ (^|[[:space:]\;\&\|\{\\])(source|\.)[[:space:]]+([^\;\&\|[:space:]]+) ]]; then
      item=${BASH_REMATCH[3]//[\"\']/}
      if [[ $item == '<('* ]]; then
        key=${item#\<\(}
        grep -qE "(^|[^A-Za-z0-9_-])$key([^A-Za-z0-9_-]|$)" "$code" && continue
      else
        tail=${item#\~}; tail=${tail#\$HOME}; tail=${tail#\$\{HOME\}}; tail=${tail#\$ZSH_DIR}; tail=${tail#\$\{ZSH_DIR\}}
        [[ $tail == '$'* ]] && continue                 # variable de boucle : mécanique interne
        grep -qF -- "$tail" "$code" && continue
      fi
    elif [[ $l =~ eval[[:space:]]+\"?\$\(([A-Za-z0-9_.-]+) ]]; then
      grep -qE "(^|[^A-Za-z0-9_-])${BASH_REMATCH[1]}([^A-Za-z0-9_-]|$)" "$code" && continue
    elif [[ $l =~ ^bindkey[[:space:]]+-v ]]; then
      grep -qE '^[[:space:]]*bindkey[[:space:]]+-v' "$code" && continue
    else
      continue                                          # setopt, zstyle, if/fi… : ignorés
    fi
    printf '%s\n' "$line"
  done
}

info "Écriture des configurations"
install_conf "$KITTY_DIR/katty.py" write_katty_py
install_conf "$KITTY_DIR/kitty.conf" write_kitty_conf adapt_kitty_conf
if [[ -n $KITTY_DISABLED ]]; then
  warn "kitty $KITTY_VER ne connaît pas ces réglages (désactivés dans kitty.conf) :"
  printf '%s\n' "$KITTY_DISABLED" | sed 's/^/      /'
fi
install_conf "$HOME/.p10k.zsh" write_p10k_zsh
install_conf "$HOME/.zshrc"    write_zshrc
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}"/zsh/init-*.zsh   # caches d'init régénérés au prochain shell

if [[ -f $BACKUP_DIR/.zshrc ]]; then
  CUSTOM=$(custom_zshrc_lines "$BACKUP_DIR/.zshrc" "$HOME/.zshrc" || true)
  if [[ -n $CUSTOM ]]; then
    warn "Ces lignes de ton ancien ~/.zshrc n'ont pas d'équivalent dans le nouveau."
    warn "Recopie celles dont tu as besoin dans ~/.zshrc.local (jamais écrasé) :"
    printf '%s\n' "$CUSTOM" | sed 's/^/      /'
  else
    ok "Aucune personnalisation perdue dans ~/.zshrc (ancienne version : $(tilde "$BACKUP_DIR"))"
  fi
fi

# ------------------------------------------------------------
#  7) git : diffs lisibles avec delta (seulement si aucun pager n'est réglé)
# ------------------------------------------------------------
if have delta && have git; then
  current_pager=$(git config --global --get core.pager 2>/dev/null || true)
  if [[ -z $current_pager ]]; then
    git config --global core.pager delta
    git config --global interactive.diffFilter 'delta --color-only'
    git config --global delta.navigate true
    git config --global delta.line-numbers true
    git config --global delta.syntax-theme TwoDark
    ok "git : diffs en couleur avec numéros de ligne (delta)"
  elif [[ $current_pager == delta* ]]; then
    ok "git : delta déjà configuré"
  fi
fi

# ------------------------------------------------------------
#  8) Zsh comme shell par défaut
# ------------------------------------------------------------
ZSH_BIN=$(command -v zsh)
CURRENT_SHELL=$(getent passwd "$(id -un)" | cut -d: -f7)
if [[ $CURRENT_SHELL != "$ZSH_BIN" && $(basename "$CURRENT_SHELL") != zsh ]]; then
  info "Shell par défaut"
  ans=O
  if (( ! ASSUME_YES )); then
    if [[ -t 0 ]]; then
      read -r -p "Passer zsh en shell par défaut ? [O/n] " ans || ans=n
    else
      ans=n
    fi
  fi
  if [[ ${ans:-O} =~ ^[OoYy]$ ]]; then
    if chsh -s "$ZSH_BIN"; then
      ok "Shell par défaut : $ZSH_BIN (effectif à la prochaine connexion)"
    else
      warn "chsh a échoué. Essaie : sudo chsh -s $ZSH_BIN $(id -un)"
    fi
  fi
fi

# ------------------------------------------------------------
#  9) Vérifications
# ------------------------------------------------------------
info "Vérifications"
if have kitty; then
  if [[ -n $KITTY_VER ]] && ! ver_ge "$KITTY_VER" 0.37.0; then
    warn "kitty $KITTY_VER est ancien : relance avec --kitty-official pour la dernière version."
  else
    ok "kitty $KITTY_VER"
  fi
  if kitty +runpy 'import sys; p = sys.argv[-1]; compile(open(p, encoding="utf-8").read(), p, "exec")' \
       "$KITTY_DIR/katty.py" >>"$LOG" 2>&1; then
    ok "Panneaux responsive (katty.py) chargeables par kitty"
  else
    warn "katty.py ne se charge pas dans ce kitty (voir $LOG)"
  fi
else
  warn "kitty introuvable : relance avec --kitty-official pour l'installer dans ~/.local"
fi

if [[ $(fc-match -f '%{family}' 'JetBrainsMono Nerd Font Mono' 2>/dev/null || true) == *JetBrainsMono* ]]; then
  ok "Police JetBrainsMono Nerd Font Mono disponible"
else
  warn "La police n'est pas encore visible (déconnecte-toi / reconnecte-toi)"
fi

zsh_start() {  # zsh interactif dans un pseudo-terminal, comme dans kitty ; affiche ses messages
  if have script; then
    (cd "$HOME" && TERM=xterm-256color script -qec 'zsh -i -c exit' /dev/null </dev/null 2>&1 | tr -d '\r')
  else
    (cd "$HOME" && TERM=xterm-256color zsh -i -c exit </dev/null 2>&1 >/dev/null)
  fi
}
ZSH_ERR=$(zsh_start) || true            # 1er lancement : crée les caches
ZSH_ERR=$(zsh_start) || true
if [[ -n $ZSH_ERR ]]; then
  warn "zsh affiche des messages au démarrage :"
  printf '%s\n' "$ZSH_ERR" | head -n 15 | sed 's/^/      /'
else
  ok "zsh démarre sans erreur"
fi
t0=$(date +%s%N)
for _ in 1 2 3 4 5; do zsh_start >/dev/null || true; done
t1=$(date +%s%N)
ok "Démarrage de zsh : ~$(( (t1 - t0) / 5000000 )) ms (le prompt s'affiche avant, grâce à l'instant prompt)"

# ------------------------------------------------------------
#  Fin
# ------------------------------------------------------------
printf '\n%s╭──────────────────────────────────────────────────────╮%s\n' "$C_PINK" "$C_OFF"
printf   '%s│%s  Katty Noir v3 installé.                           %s│%s\n' "$C_PINK" "$C_OFF" "$C_PINK" "$C_OFF"
printf   '%s│%s  Ferme puis relance kitty pour tout activer.         %s│%s\n' "$C_PINK" "$C_OFF" "$C_PINK" "$C_OFF"
printf   '%s│%s  Aide-mémoire des raccourcis : tape %skatty%s          %s│%s\n' "$C_PINK" "$C_OFF" "$C_BOLD" "$C_OFF" "$C_PINK" "$C_OFF"
printf   '%s╰──────────────────────────────────────────────────────╯%s\n\n' "$C_PINK" "$C_OFF"

cat <<EOF
${C_PINK}Panneaux kitty (responsive)${C_OFF}
  ctrl+shift+entrée   nouveau panneau ; jamais sous 30×7, sinon nouvel onglet
  ctrl+shift+l / d    nouveau panneau à droite / en dessous
  ctrl+alt+h/j/k/l    changer de panneau      ctrl+alt+maj+h/j/k/l  redimensionner
  ctrl+shift+z        zoom (aller-retour)     ctrl+shift+b          rééquilibrer
${C_PINK}Nouveautés${C_OFF}
  ctrl+shift+f recherche dans l'historique · ctrl+shift+m surligne flags/IP/erreurs
  alt+1…9 onglets · Échap Échap = sudo · ctrl+g ctrl+b branches git · frg, fe, x, z

${C_DIM}Revenir en arrière : ./install.sh --restore      Journal : $(tilde "$LOG")${C_OFF}
EOF
