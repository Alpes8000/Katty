# Katty Noir

> Un installateur unique pour avoir **kitty + zsh + Powerlevel10k** configurés, rapides et « responsive » : thème noir/rose, panneaux qui ne cassent jamais, prompt qui s'adapte à la taille du panneau, complétion avec aperçu, et une boîte à outils pensée pour le terminal d'un pentester / étudiant en cybersécurité.

Un seul script : `install.sh` (v3). Il installe les paquets, les plugins, la police, écrit `kitty.conf`, `katty.py`, `.zshrc` et `.p10k.zsh`, sauvegarde tout ce qu'il remplace, et peut être relancé à volonté.

- **Distributions** : Fedora (dnf), Debian / Ubuntu (apt), Arch (pacman), openSUSE (zypper)
- **Thème** : « Katty Noir » : fond noir, accent rose `#e01247`, police JetBrainsMono Nerd Font Mono
- **Idempotent** : un fichier déjà à jour n'est pas touché ; les plugins sont mis à jour
- **Réversible** : `./install.sh --restore` remet tes anciens fichiers à l'octet près

---

## Sommaire

1. [Installation](#installation)
2. [Ce qui est installé](#ce-qui-est-installé)
3. [Différences avec kitty « de base »](#différences-avec-kitty--de-base-)
4. [Le garde-fou des panneaux (`katty.py`)](#le-garde-fou-des-panneaux-kattypy)
5. [Raccourcis clavier kitty](#raccourcis-clavier-kitty)
6. [Raccourcis clavier zsh](#raccourcis-clavier-zsh)
7. [Alias et commandes](#alias-et-commandes)
8. [Complétion (tab) avec aperçu](#complétion-tab-avec-aperçu)
9. [Prompt responsive](#prompt-responsive)
10. [Zsh : performances et options](#zsh--performances-et-options)
11. [git avec delta](#git-avec-delta)
12. [Options de l'installateur](#options-de-linstallateur)
13. [Sauvegarde et restauration](#sauvegarde-et-restauration)
14. [Personnalisation](#personnalisation)

---

## Installation

```bash
git clone https://github.com/Alpes8000/Katty.git
cd Katty
chmod +x install.sh
./install.sh
```

Ensuite, **ferme toutes les fenêtres kitty et relance-les** : le garde-fou des panneaux (`katty.py`) ne se charge qu'au démarrage de kitty.

Tape `katty` dans le terminal pour afficher l'aide-mémoire des raccourcis.

> ⚠️ Le script demande `sudo` (installation de paquets) et **remplace** `kitty.conf` et `.zshrc`. Tes anciens fichiers sont sauvegardés automatiquement dans `~/.config-backup-<date>`. Ne le lance pas en root.

Sans droits sudo : `./install.sh --no-sudo` (tout le reste s'installe dans `~/.local`).

---

## Ce qui est installé

| Catégorie | Éléments |
|---|---|
| Terminal | kitty (ou la dernière version officielle avec `--kitty-official`) |
| Shell | zsh (proposé comme shell par défaut, `-y` pour accepter sans question) |
| Prompt | Powerlevel10k |
| Police | JetBrainsMono Nerd Font Mono (variante *Mono* : icônes sur 1 cellule) |
| Plugins zsh | zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions, zsh-history-substring-search, fzf-tab, fzf-git |
| Outils CLI | fzf (≥ 0.48), eza, bat, ripgrep (`rg`), fd, zoxide, git-delta |
| Notifications | libnotify (notification quand une longue commande se termine) |

- Les plugins sont clonés dans `~/.zsh/` (les 7 dépôts sont téléchargés **en parallèle**).
- Les outils absents ou trop vieux dans la distribution (fzf, eza, zoxide) sont installés dans `~/.local`.
- Sous Debian/Ubuntu, `batcat` et `fdfind` sont liés vers `bat` et `fd`.
- La police est téléchargée en `.tar.xz` (≈ 7 Mo au lieu de 134 Mo en `.zip`).
- Les paquets sont installés en une seule fois, avec un repli paquet par paquet si l'un manque.

### Fichiers écrits

| Fichier | Rôle |
|---|---|
| `~/.config/kitty/kitty.conf` | Configuration kitty (adaptée automatiquement à ta version) |
| `~/.config/kitty/katty.py` | Module kitty : garde-fou des panneaux (split, resize, watcher) |
| `~/.zshrc` | Configuration zsh |
| `~/.p10k.zsh` | Thème Powerlevel10k |
| `~/.zshrc.local` | **Tes ajouts perso** : chargé à la fin, jamais écrasé |
| `~/.config-backup-<date>/` | Sauvegarde des anciens fichiers à chaque lancement |
| `~/.cache/katty-install.log` | Journal de l'installation |

---

## Différences avec kitty « de base »

| Sujet | kitty par défaut | Katty Noir |
|---|---|---|
| Nouveau panneau (`ctrl+shift+entrée`) | Coupe sans taille minimale : après ~6 splits, l'affichage se raye | Taille minimale 30 × 7 ; sans place, ouverture dans un **nouvel onglet** (même dossier) |
| Sens de la coupe | Selon le layout | Choisi automatiquement : on coupe le **côté le plus long** |
| Redimensionnement | Libre, peut écraser un panneau | Refusé s'il fait passer un panneau sous 10 × 3 |
| Fenêtre qui rétrécit | Rien de particulier | Panneaux égalisés, puis **zoom automatique** sur le panneau actif + notification |
| Marges | Fixes | Larges avec 1 seul panneau (8/12), serrées en split (4/6) |
| Layouts | Tous | `splits` + `stack` (zoom) |
| Onglets | Style par défaut | Powerline arrondi, numéro, marqueurs activité/cloche, nombre de panneaux, icône de zoom ; masqués s'il n'y en a qu'un |
| Aller à l'onglet *n* | Raccourcis par défaut | `alt+1…9`, y compris en **AZERTY sans Maj** |
| Recherche dans l'historique | `ctrl+shift+h` (pager) | + `ctrl+shift+f` : recherche dans tout le scrollback |
| Surlignage | Aucun | `ctrl+shift+m` : flags CTF, IP et erreurs |
| Barre de défilement | Absente | Fine, rose, visible **seulement** quand on remonte l'historique |
| Curseur | Plein, clignote en continu | Creux sans focus, arrête de clignoter après 15 s, traînée courte |
| Transparence | Opaque | `background_opacity 0.78` (+ flou sous KDE/macOS), réglable à la volée |
| Panneaux inactifs | Identiques | Légèrement estompés (`inactive_text_alpha 0.72`) |
| Notifications | Aucune | Notification bureau si une commande > 20 s finit dans un onglet/panneau non visible |
| Historique | 2 000 lignes | 20 000 lignes |
| Copie | Manuelle | `copy_on_select` vers le presse-papier |
| URL | Détectées | + soulignées en vague, bleues, cible affichée au survol |
| Cloche | Sonore | Désactivée (cloche visuelle sur l'onglet) |
| Compatibilité de version | Option inconnue → fenêtre d'erreur | Option inconnue **mise en commentaire** automatiquement |

---

## Le garde-fou des panneaux (`katty.py`)

**Le bug d'origine :** chaque `ctrl+shift+entrée` coupe le panneau actif en deux, sans taille minimale. Avec des marges de 12 et 18 pt et les bordures, au 6ᵉ split le panneau fait ~30 px de large, soit moins que ses propres marges. kitty calcule alors une largeur **négative** (−40 px relevé, soit 0 colonne) et les caractères s'étirent en rayures sur toute la fenêtre.

**Le correctif :** un module kitty dont les règles sont exprimées **en caractères**. Il lit la vraie taille des caractères, des marges, des bordures et de la mise à l'échelle : il marche donc sur n'importe quel écran, quelle que soit la définition ou la taille de police.

| Règle | Comportement |
|---|---|
| Nouveau panneau | Créé seulement si les deux moitiés gardent **≥ 30 colonnes × 7 lignes** |
| Pas de place dans le panneau actif | Le **plus grand** panneau de l'onglet est coupé à la place |
| Plus de place nulle part | Le panneau s'ouvre dans un **nouvel onglet**, dans le même dossier |
| Resize | Refusé si un panneau passerait sous **10 × 3** |
| Fenêtre qui rétrécit (demi-écran, petit moniteur, police agrandie) | Panneaux d'abord égalisés ; si ça ne suffit pas, **zoom automatique** sur le panneau actif + notification |
| Retour à la normale | Les autres panneaux reviennent dès qu'il y a de la place, ou avec `ctrl+shift+z` |

Résultat mesuré : au maximum **8 panneaux** sur une fenêtre de 125 × 34, le 9ᵉ s'ouvre dans un nouvel onglet. Même en contournant le correctif (splits bruts de kitty), l'onglet passe en zoom au lieu de se rayer. Aucune largeur négative.

---

## Raccourcis clavier kitty

> `katty` dans le terminal affiche le même aide-mémoire.

### Panneaux

| Raccourci | Action |
|---|---|
| `ctrl+shift+entrée` | Nouveau panneau (coupe le côté le plus long, avec garde-fou) |
| `ctrl+shift+l` | Nouveau panneau à **droite** |
| `ctrl+shift+d` | Nouveau panneau **en dessous** |
| `ctrl+alt+h` / `j` / `k` / `l` | Aller au panneau gauche / bas / haut / droite |
| `ctrl+alt+shift+h` / `l` | Panneau plus étroit / plus large (pas de 3) |
| `ctrl+alt+shift+j` / `k` | Panneau plus haut / moins haut (pas de 2) |
| `ctrl+shift+z` | Zoom du panneau (aller-retour) |
| `ctrl+shift+o` | Pivoter le split (côte à côte ⇄ empilé) |
| `ctrl+shift+b` | Rééquilibrer tous les panneaux |
| `ctrl+shift+f7` | Choisir un panneau par numéro |
| `ctrl+shift+f8` | Échanger deux panneaux |
| `ctrl+shift+r` | Mode redimensionnement interactif (défaut kitty) |
| `ctrl+shift+w` | Fermer le panneau (défaut kitty) |

### Onglets et fenêtres

| Raccourci | Action |
|---|---|
| `ctrl+shift+t` | Nouvel onglet **dans le même dossier** |
| `alt+1` … `alt+9` | Aller à l'onglet *n* |
| `alt+&` `é` `"` `'` `(` `-` `è` `_` `ç` | Idem, en **AZERTY sans Maj** (onglets 1 à 9) |
| `ctrl+shift+←` / `→` | Onglet précédent / suivant (défaut kitty) |
| `ctrl+shift+alt+t` | Renommer l'onglet (défaut kitty) |
| `ctrl+shift+n` | Nouvelle fenêtre **dans le même dossier** |

### Historique et recherche

| Raccourci | Action |
|---|---|
| `ctrl+shift+f` | **Chercher** dans tout l'historique du terminal |
| `ctrl+shift+↑` / `↓` | Sauter au prompt précédent / suivant |
| `ctrl+shift+g` | Sortie de la dernière commande dans un pager (défaut kitty) |
| `ctrl+shift+h` | Tout l'historique dans un pager (défaut kitty) |
| `ctrl+shift+m` | **Surligner** (bascule) : flags CTF en jaune, adresses IP en bleu, erreurs en rose |

Le surlignage `ctrl+shift+m` repère :

- **Jaune** : les flags `flag{…}`, `ctf{…}`, `htb{…}`, `thm{…}`, `picoctf{…}`, `fcsc{…}`, `dghack{…}`, `ecw{…}`, `ductf{…}`
- **Bleu** : les adresses IPv4
- **Rose** : `error`, `failed`, `denied`, `panic`, `Traceback`, `segmentation fault`…

### Divers (défauts kitty conservés)

| Raccourci | Action |
|---|---|
| `ctrl+shift+e` | Ouvrir une URL affichée à l'écran |
| `ctrl+shift+p` puis `f` | Insérer un chemin affiché (`p` puis `l` : une ligne, `p` puis `w` : un mot) |
| `ctrl+shift+u` | Saisir un caractère Unicode / emoji |
| `ctrl+shift+delete` | Effacer l'écran |
| `ctrl+shift+=` / `-` / `backspace` | Police plus grande / plus petite / par défaut |
| `ctrl+shift+a` puis `m` / `l` | Fond plus / moins transparent |

> `ctrl+shift+a` fonctionne enfin : à cause d'un commentaire en fin de ligne, `dynamic_background_opacity` était lu comme « non » dans l'ancienne config.

---

## Raccourcis clavier zsh

| Raccourci | Action |
|---|---|
| `tab` | Complétion fzf avec **aperçu** ; `<` / `>` pour changer de groupe de résultats |
| `ctrl+r` | Historique avec fzf |
| `ctrl+t` | Choisir des fichiers avec fzf (aperçu bat / eza) |
| `alt+c` | Choisir un dossier et y aller (aperçu eza) |
| `ctrl+/` | Afficher / masquer l'aperçu fzf |
| `↑` / `↓` | Historique **filtré par le début de la ligne** déjà tapée |
| `ctrl+espace` | Accepter la suggestion grise (autosuggestions) |
| `Échap Échap` | **Ajoute ou retire `sudo`** devant la ligne (ou la commande précédente si la ligne est vide) |
| `ctrl+z` | Ligne **vide** : reprend le programme suspendu (aller-retour vim ⇄ shell, sans polluer l'historique) ; ligne **en cours** : la met de côté, elle revient après la commande suivante |
| `ctrl+x` `ctrl+e` | Ouvre la ligne dans `$EDITOR` |
| `ctrl+→` / `ctrl+←` | Mot suivant / précédent |
| `Début` / `Fin` | Début / fin de ligne |
| `Suppr` / `ctrl+Suppr` | Supprimer un caractère / un mot |
| `ctrl+retour arrière` | Supprimer le mot précédent |

### fzf-git (`ctrl+g` puis…)

| Raccourci | Action |
|---|---|
| `ctrl+g` `ctrl+f` | Fichiers git |
| `ctrl+g` `ctrl+b` | Branches |
| `ctrl+g` `ctrl+t` | Tags |
| `ctrl+g` `ctrl+h` | Commits |
| `ctrl+g` `ctrl+s` | Stashes |
| `ctrl+g` `?` | Afficher tous les raccourcis fzf-git |

> Le mode de saisie est **emacs** (`bindkey -e`) même si `$EDITOR` est vim. Pour le mode vi : ajoute `bindkey -v` dans `~/.zshrc.local`.

---

## Alias et commandes

### Alias

| Alias | Commande réelle | Utilité |
|---|---|---|
| `ls` | `eza --icons=auto --group-directories-first` | Liste avec icônes (repli : `ls --color=auto --group-directories-first`) |
| `ll` | `eza -l --icons=auto --group-directories-first --git` | Liste longue + statut git |
| `la` | `eza -la --icons=auto --group-directories-first --git` | Idem avec fichiers cachés |
| `lt` | `eza --tree --level=2 --icons=auto --group-directories-first` | Arborescence sur 2 niveaux |
| `l` | `ll` | Raccourci |
| `bat` | `batcat` | Sous Debian/Ubuntu |
| `fd` | `fdfind` | Sous Debian/Ubuntu |
| `grep` | `grep --color=auto` | Couleurs |
| `diff` | `diff --color=auto` | Couleurs |
| `ip` | `ip -c=auto` | Couleurs seulement dans un terminal (pas de codes parasites dans `ip a \| grep tun0`) |
| `ips` | `ip -br -c=auto addr` | **Toutes les IP**, une ligne par interface |
| `ports` | `ss -tulpn` | Ports en écoute + processus |
| `df` | `df -h` | Tailles lisibles |
| `free` | `free -h` | Tailles lisibles |
| `mkdir` | `mkdir -p` | Crée les parents |
| `path` | `print -l $path` | Un dossier du `PATH` par ligne |
| `..` / `...` / `....` | `cd ..` / `cd ../..` / `cd ../../..` | Remonter |
| `icat` | `kitten icat` | Afficher une image dans le terminal |
| `kdiff` | `kitten diff` | Diff côte à côte (images comprises) |
| `z` | zoxide | Saute au dossier le plus fréquenté qui correspond (`z dossier`) |

### Fonctions

| Commande | Action |
|---|---|
| `x <archive>…` | **Extrait n'importe quelle archive** : `.tar.gz/.tgz`, `.tar.bz2`, `.tar.xz`, `.tar.zst`, `.tar`, `.gz`, `.bz2`, `.xz`, `.zst`, `.zip/.jar/.apk/.whl/.war`, `.7z`, `.rar`, `.deb`, `.rpm` |
| `fe [motif]` | Ouvre dans l'éditeur un fichier choisi avec fzf (aperçu bat) |
| `frg [texte]` | **Recherche en direct dans le contenu** des fichiers (ripgrep + fzf, aperçu avec la ligne surlignée, `entrée` ouvre l'éditeur à la bonne ligne) |
| `fkill [signal]` | Tuer un ou plusieurs processus choisis avec fzf (`tab` : sélection multiple ; signal 15 par défaut) |
| `mkcd <dossier>` | Crée un dossier et y entre |
| `bak <fichier>…` | Copie `fichier` en `fichier.bak-<date-heure>` |
| `lhost` | Affiche l'**IP du tunnel VPN** (`tun*`, `wg*`, `tailscale*`) et la **copie dans le presse-papier** |
| `serve [port]` | Sert le dossier courant en HTTP (port 8000 par défaut) et affiche l'URL côté VPN |
| `reload` | Recharge le shell en vidant les caches |
| `katty` | Affiche l'aide-mémoire |

### Petits plus du shell

- **URL collée** : automatiquement mise entre guillemets (`?`, `&`, `#` sans danger).
- **Commande introuvable** : propose le paquet qui la fournit (Ubuntu/Debian, Arch avec `pkgfile`).
- **Pages de manuel en couleur** (palette Katty).
- **`$EDITOR`** : détecté automatiquement (`nvim` → `vim` → `nano` → `vi`) s'il n'est pas déjà défini.
- **`PATH`** : `~/.local/bin`, `~/.cargo/bin` et `~/go/bin` ajoutés s'ils existent.
- **`cd` automatique** : taper un nom de dossier suffit (`AUTO_CD`).

---

## Complétion (tab) avec aperçu

`tab` ouvre fzf-tab avec un aperçu adapté à la commande :

| Commandes | Aperçu |
|---|---|
| `cd`, `z`, `zi`, `pushd`, `eza`, `ls`, `rmdir` | Contenu du dossier (eza) |
| `cat`, `bat`, `less`, `head`, `tail`, `nano`, `vi`, `vim`, `nvim`, `code`, `cp`, `mv`, `rm`, `file`, `strings`, `xxd`, `chmod`, `source` | Contenu du fichier (bat) ou du dossier |
| `kill`, `ps` | Ligne de commande complète du processus |
| `systemctl …` | `systemctl status` du service |
| Variables (`$`, `export`, `unset`) | Valeur de la variable |
| `git add`, `git diff`, `git restore` | `git diff` du fichier |
| `git log` | Graphe des 20 derniers commits |

Complétion insensible à la casse, avec correspondance partielle sur `. _ -`.

---

## Prompt responsive

Prompt Powerlevel10k sur deux lignes, cadre arrondi rose (`╭─ … ─╮` / `╰─❯`), sans fond.

**Éléments** : icône de la distribution, dossier, état git, virtualenv ┃ code d'erreur, durée de la commande, jobs en arrière-plan, version de Rust, IP du VPN, `user@host`, heure.

Quand le panneau rétrécit, les éléments disparaissent **un par un** (recalculé immédiatement au redimensionnement, sans attendre la commande suivante) :

| Largeur du panneau | Ce qui disparaît |
|---|---|
| < 100 colonnes | L'heure |
| < 90 colonnes | La version de Rust |
| < 70 colonnes | L'icône de la distribution |
| < 60 colonnes | `user@host`, durée de la commande, jobs |

Ils reviennent quand le panneau s'élargit. L'**IP du VPN** et le **code d'erreur** restent tant que la ligne a la place. La version de Rust ne s'affiche **que dans un projet Cargo**.

Les anciens prompts sont réduits à `╰─❯ commande` (*transient prompt*), ce qui évite les traînées de `─` quand un panneau rétrécit.

---

## Zsh : performances et options

**Démarrage ≈ 3× plus rapide** (≈ 60 ms au lieu de ≈ 199 ms, mesuré) :

- scripts d'initialisation (fzf, zoxide, dircolors) **mis en cache**, régénérés seulement quand le binaire change ;
- base de complétion reconstruite **une fois par jour** et précompilée ;
- plugins précompilés ;
- si un plugin manque, le shell démarre quand même, sans erreur.

**Historique** : 100 000 commandes, partagé entre les sessions, doublons supprimés, commandes précédées d'un espace non enregistrées, horodatage.

**Options utiles** : `AUTO_CD`, `AUTO_PUSHD`, `COMPLETE_IN_WORD`, `INTERACTIVE_COMMENTS`, pas de bip, `ctrl+w` / `ctrl+flèches` s'arrêtent aux `/ . =`.

**Coloration** : syntaxe colorée palette Katty (commandes en vert, mots réservés en rose, options en bleu, chaînes en jaune, commandes inconnues en rouge gras), suggestions grises, filtre d'historique surligné.

---

## git avec delta

Si **aucun pager git n'est configuré**, l'installateur installe `git-delta` et règle :

```
core.pager            = delta
interactive.diffFilter = delta --color-only
delta.navigate        = true
delta.line-numbers    = true
delta.syntax-theme    = TwoDark
```

Pour annuler : `git config --global --unset core.pager`. Si un pager est déjà configuré, rien n'est modifié.

---

## Options de l'installateur

```
./install.sh [options]
```

| Option | Effet |
|---|---|
| `-y`, `--yes` | zsh en shell par défaut sans poser la question |
| `--no-sudo` | N'installe aucun paquet système (tout le reste en local) |
| `--kitty-official` | Installe la dernière version officielle de kitty dans `~/.local` (utile si la distribution fournit un vieux kitty) |
| `--restore [DOSSIER]` | Remet les fichiers de la dernière sauvegarde (`~/.config-backup-*`) ou de `DOSSIER`, puis s'arrête |
| `-h`, `--help` | Affiche l'aide |

Vérifications finales automatiques : module kitty chargeable, police visible, zsh qui démarre sans erreur, temps de démarrage.

L'installateur repère aussi les **lignes perso de ton ancien `.zshrc`** (alias, variables, PATH, source, eval, fonctions) qui seraient perdues, et te dit de les recopier dans `~/.zshrc.local`.

---

## Sauvegarde et restauration

- À **chaque lancement**, les fichiers remplacés sont copiés dans `~/.config-backup-<date>`.
- Un fichier déjà à jour n'est ni réécrit ni sauvegardé.
- Retour en arrière : `./install.sh --restore` (dernière sauvegarde) ou `./install.sh --restore ~/.config-backup-<date>`.
- La restauration rend les fichiers d'origine **à l'octet près**.

---

## Personnalisation

- **Tes alias, variables, fonctions** : `~/.zshrc.local` (chargé en dernier, jamais écrasé par l'installateur).
- **Mode vi** : `bindkey -v` dans `~/.zshrc.local`.
- **Barre de titre** : décommente `hide_window_decorations yes` dans `kitty.conf`.
- **Seuils des panneaux** : `MIN_COLS, MIN_LINES = 30, 7` (taille minimale d'un split) et `HARD_COLS, HARD_LINES = 10, 3` (plancher absolu, sous lequel le zoom automatique se déclenche) dans `katty.py`.
- **Thème du prompt** : `p10k configure` ou édition de `~/.p10k.zsh`.

> Attention : si tu modifies `kitty.conf`, `katty.py` ou `.p10k.zsh` à la main, une relance de `install.sh` les remplace par la version du script (l'ancienne est sauvegardée dans `~/.config-backup-<date>`). Les réglages durables côté zsh vont dans `~/.zshrc.local`.


---

## Base de la configuration

Le squelette du `kitty.conf` (structure en sections, traînée du curseur, accent rose `#e01247`) et la **palette de couleurs** viennent de la configuration kitty de [Helphy](https://github.com/Helphyy). Katty part de cette base et la complète.

| Réglage | Config de base de [Helphy](https://github.com/Helphyy) | Katty |
|---|---|---|
| Palette `color1` à `color15`, curseur, sélection, texte | Reprise telle quelle | Identique, sauf `color0` |
| Fond | `#1b1f27` | `#000000` (noir pur) |
| `color0` | `#1b1f27` | `#1a1a1a` |
| Bordure inactive | `#2a2f3a` | `#2a2a2a` |
| Opacité du fond | `0.80` | `0.78` |
| Police | `JetBrainsMono Nerd Font` | `JetBrainsMono Nerd Font Mono` (icônes sur 1 cellule) |
| Marges | `4` / `4` | `8 12` avec un seul panneau, `4 6` en split |
| Seuil de la traînée du curseur | `0` | `2` |
| Confirmation à la fermeture | `0` | `-1` (seulement si une commande tourne) |
| Panneaux, onglets, raccourcis, recherche, surlignage | Absents | Ajoutés (`katty.py`, `alt+1…9`, `ctrl+shift+f`, `ctrl+shift+m`…) |
| Zsh, prompt Powerlevel10k, alias, installateur | Absents | Ajoutés |

## Crédits

Squelette et palette de la config kitty : [Helphy](https://github.com/Helphyy).

Construit sur [kitty](https://sw.kovidgoyal.net/kitty/), [zsh](https://www.zsh.org/), [Powerlevel10k](https://github.com/romkatv/powerlevel10k), [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions), [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting), [zsh-completions](https://github.com/zsh-users/zsh-completions), [zsh-history-substring-search](https://github.com/zsh-users/zsh-history-substring-search), [fzf-tab](https://github.com/Aloxaf/fzf-tab), [fzf](https://github.com/junegunn/fzf), [fzf-git.sh](https://github.com/junegunn/fzf-git.sh), [eza](https://github.com/eza-community/eza), [bat](https://github.com/sharkdp/bat), [ripgrep](https://github.com/BurntSushi/ripgrep), [fd](https://github.com/sharkdp/fd), [zoxide](https://github.com/ajeetdsouza/zoxide), [delta](https://github.com/dandavison/delta) et [Nerd Fonts](https://www.nerdfonts.com/) (JetBrainsMono).

