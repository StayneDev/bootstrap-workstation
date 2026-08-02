#!/bin/bash

# =============================================================================
# POST-FORMAT SETUP — multi-distro (Arch, Ubuntu/Debian, Fedora)
# =============================================================================

set -e

if [ "$EUID" -eq 0 ]; then
  echo "Execute como usuario comum (nao root)."
  exit 1
fi

# --- Origem dos assets (clonado x streamed) ---
# Clonado: perfis.sh, perfis/*.perfil e os assets do firefox/vscode estão ao
# lado deste script. Streamed (`bash <(curl ...)`): BASH_SOURCE é um FIFO
# (/dev/fd/NN) e não existe diretório irmão — sem isto o source abaixo morre
# sob `set -e`, o FIFO fecha e o curl da chamada reporta "(23) Failure writing
# output to destination", que esconde a causa real.
#
# O tarball do ref traz TODOS os assets de uma vez (~28K), então não há lista
# de arquivos aqui para divergir do que o repo realmente tem (um perfil novo
# entra sozinho). BOOTSTRAP_REF deve casar com o ref do one-liner.
BOOTSTRAP_REF="${BOOTSTRAP_REF:-main}"
DOTFILES_RAW="https://raw.githubusercontent.com/StayneDev/bootstrap-workstation/$BOOTSTRAP_REF/machine"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

if [ ! -f "$SCRIPT_DIR/perfis.sh" ]; then
  echo "[INFO] Modo streamed — baixando assets do ref '$BOOTSTRAP_REF'"
  BOOTSTRAP_TMP="$(mktemp -d)"
  trap 'rm -rf "$BOOTSTRAP_TMP"' EXIT
  curl -fsSL "https://codeload.github.com/StayneDev/bootstrap-workstation/tar.gz/refs/heads/$BOOTSTRAP_REF" \
    | tar xz -C "$BOOTSTRAP_TMP" --strip-components=1 \
    || { echo "[ERRO] Falha ao baixar os assets do ref '$BOOTSTRAP_REF'." >&2; exit 1; }
  SCRIPT_DIR="$BOOTSTRAP_TMP/machine"
  [ -f "$SCRIPT_DIR/perfis.sh" ] \
    || { echo "[ERRO] perfis.sh ausente no tarball de '$BOOTSTRAP_REF'." >&2; exit 1; }
fi

# --- Perfis, respostas e conferência (#21, #22, #24) ---
source "$SCRIPT_DIR/perfis.sh"

# --- Deteccao de distro ---
detect_distro() {
  if command -v pacman &>/dev/null; then DISTRO="arch"
  elif command -v apt-get &>/dev/null; then DISTRO="debian"
  elif command -v dnf &>/dev/null; then DISTRO="fedora"
  else echo "Distro nao suportada." && exit 1
  fi
  echo "[INFO] Distro detectada: $DISTRO"
}

# =============================================================================
# 1. PACOTES BASE
# =============================================================================
install_base() {
  echo -e "\n[provisionar] Instalando pacotes base..."

  case $DISTRO in
    arch)
      sudo pacman -Syu --noconfirm
      sudo pacman -S --noconfirm --needed \
        git curl zsh zsh-completions \
        neofetch cmatrix \
        tailscale \
        ttf-liberation ttf-nerd-fonts-symbols-common noto-fonts noto-fonts-emoji \
        power-profiles-daemon wireplumber \
        flatpak
      # yay
      if ! command -v yay &>/dev/null; then
        sudo pacman -S --noconfirm --needed base-devel
        git clone https://aur.archlinux.org/yay.git /tmp/yay
        cd /tmp/yay && makepkg -si --noconfirm && cd - && rm -rf /tmp/yay
      fi
      # VSCode
      yay -S --noconfirm visual-studio-code-bin
      ;;
    debian)
      # Garante repos online — remove cdrom e adiciona bookworm se ausente
      sudo sed -i '/^deb cdrom:/d' /etc/apt/sources.list
      if ! grep -q "deb.debian.org" /etc/apt/sources.list; then
        cat <<'EOF' | sudo tee /etc/apt/sources.list > /dev/null
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF
        echo "  [OK] sources.list atualizado para repositorios online."
      fi
      sudo apt update && sudo apt upgrade -y
      sudo apt install -y git curl zsh neofetch cmatrix flatpak
      # VSCode — usa curl (wget pode nao estar disponivel)
      curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg > /dev/null
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
      VSCODE_UPDATE=$(sudo apt update 2>&1 || true)
      if echo "$VSCODE_UPDATE" | grep -q "NO_PUBKEY"; then
        echo "  [AVISO] Chave GPG do VSCode invalida — removendo repo e pulando instalacao."
        sudo rm -f /etc/apt/sources.list.d/vscode.list /usr/share/keyrings/microsoft.gpg
        sudo apt update
      else
        sudo apt install -y code
      fi
      # Tailscale
      curl -fsSL https://tailscale.com/install.sh | sh
      ;;
    fedora)
      sudo dnf upgrade -y
      sudo dnf install -y git curl zsh neofetch cmatrix flatpak
      # VSCode
      sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
      sudo tee /etc/yum.repos.d/vscode.repo > /dev/null <<EOF
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
      sudo dnf install -y code
      # Tailscale
      curl -fsSL https://tailscale.com/install.sh | sh
      ;;
  esac

  # Flatpak remote
  sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

# =============================================================================
# 2. APPS VIA FLATPAK (universal)
# =============================================================================
# Discord e Steam são camada PESSOAL (perfis/pessoal.perfil) — separados na #21
# para o manifesto poder incluí-los ou não. install_flatpak_apps ficou como união.
install_discord() {
  echo -e "\n[provisionar] Instalando Discord (Flatpak)..."
  sudo flatpak install -y flathub com.discordapp.Discord
}
install_steam() {
  echo -e "\n[provisionar] Instalando Steam (Flatpak)..."
  sudo flatpak install -y flathub com.valvesoftware.Steam
}
install_flatpak_apps() {
  install_discord
  install_steam
  # Firefox nao e instalado aqui — distros ja incluem versao nativa.
  # Flatpak e usado apenas como fallback via --firefox quando nativo ausente.
}

# =============================================================================
# BRAVE ORIGIN (#23) — o Brave minimalista; gratuito no Linux
# =============================================================================
install_brave_origin() {
  echo -e "\n[provisionar] Instalando Brave Origin..."
  if command -v brave-origin &>/dev/null || command -v brave-browser-origin &>/dev/null; then
    echo "  [OK] Brave Origin já instalado."
    return 0
  fi
  case $DISTRO in
    debian)
      # canal oficial: laptop-updates.brave.com/latest/origin serve o pacote da
      # release corrente; o endpoint linux64 entrega .deb
      local DEB=/tmp/brave-origin.deb
      if curl -fsSL "https://laptop-updates.brave.com/latest/origin/linux64" -o "$DEB" 2>/dev/null \
         && sudo apt install -y "$DEB"; then
        echo "  [OK] Brave Origin instalado via .deb oficial."
        rm -f "$DEB"
      else
        rm -f "$DEB"
        echo "  [AVISO] download direto falhou — endpoint pode ter mudado."
        echo "          Instale manualmente de https://brave.com/origin/ e re-execute."
        return 1
      fi
      ;;
    arch|fedora)
      echo "  [AVISO] Brave Origin: instalação automatizada só em Debian/Ubuntu por ora."
      echo "          Baixe em https://brave.com/origin/ — portabilidade não é prioridade (antessala, item 4)."
      return 1
      ;;
  esac
}

# =============================================================================
# CLONE DA INFRA (perfil infra) — posto de controle: clone, não merge
# =============================================================================
clone_infra() {
  echo -e "\n[fechar] Clonando bootstrap-infra (privado — exige auth)..."
  local INFRA_DIR="$HOME/repos/bootstrap-infra"
  mkdir -p "$HOME/repos"
  if [ ! -d "$INFRA_DIR/.git" ]; then
    git clone git@github.com:StayneDev/bootstrap-infra.git "$INFRA_DIR"
  fi
  echo "  [OK] posto de controle da infra pronto em $INFRA_DIR."
}

# =============================================================================
# 3. JDK 21
# =============================================================================
install_java() {
  echo -e "\n[provisionar] Instalando JDK 21..."
  case $DISTRO in
    arch)    sudo pacman -S --noconfirm --needed jdk21-openjdk ;;
    debian)
      # openjdk-21 requer backports no Bookworm
      if ! apt-cache show openjdk-21-jdk &>/dev/null; then
        BACKPORTS="deb http://deb.debian.org/debian bookworm-backports main contrib non-free"
        if ! grep -qF "bookworm-backports" /etc/apt/sources.list; then
          echo "$BACKPORTS" | sudo tee -a /etc/apt/sources.list > /dev/null
          sudo apt update
        fi
      fi
      if apt-cache show openjdk-21-jdk &>/dev/null; then
        sudo apt install -y -t bookworm-backports openjdk-21-jdk
      else
        echo "  [AVISO] openjdk-21 nao disponivel — instalando openjdk-17."
        sudo apt install -y openjdk-17-jdk
      fi
      ;;
    fedora)  sudo dnf install -y java-21-openjdk-devel ;;
  esac
}

# =============================================================================
# 4. NODE (nvm) + CLAUDE CODE
# =============================================================================
install_node_and_claude() {
  echo -e "\n[provisionar] Instalando nvm, Node e Claude Code..."

  export NVM_DIR="$HOME/.nvm"
  if [ ! -d "$NVM_DIR" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
  fi
  source "$NVM_DIR/nvm.sh"

  nvm install --lts
  nvm use --lts

  npm install -g @anthropic-ai/claude-code
}

# =============================================================================
# 5. TERMINAL — Zsh + Oh My Zsh + tema bira
# =============================================================================
setup_terminal() {
  echo -e "\n[configurar] Configurando terminal..."

  # Oh My Zsh
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  fi

  # Shell padrao para zsh
  if [ "$(getent passwd $USER | cut -d: -f7)" != "$(which zsh)" ]; then
    chsh -s "$(which zsh)"
  fi

  # .zshrc
  cat > "$HOME/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="bira"
plugins=(git)
source $ZSH/oh-my-zsh.sh

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Angular CLI autocompletion
[ "$(command -v ng)" ] && source <(ng completion script)

export PATH="$HOME/.local/bin:$PATH"
EOF

  echo "[OK] Terminal configurado. Reinicie o terminal para aplicar."
}

# =============================================================================
# UTILITARIO — copia para clipboard (Wayland ou X11)
# =============================================================================
copy_to_clipboard() {
  if command -v wl-copy &>/dev/null; then
    echo "$1" | wl-copy
  elif command -v xclip &>/dev/null; then
    echo "$1" | xclip -selection clipboard
  elif command -v xsel &>/dev/null; then
    echo "$1" | xsel --clipboard --input
  fi
}

# =============================================================================
# UTILITARIO — pausa com mensagem
# =============================================================================
pause() {
  echo ""
  echo "  >>> $1"
  read -rp "      Pressione ENTER quando terminar..."
  echo ""
}

# =============================================================================
# 6. GIT + SSH + GITHUB (runtime)
# =============================================================================
setup_git_ssh() {
  echo -e "\n[autenticar] Configurando Git e chave SSH..."

  # identidade = chave divergente entre camadas (#21): vem das respostas do
  # perfil quando existem; os literais antigos ficam como default do operador
  local GIT_NAME GIT_EMAIL
  GIT_NAME="$(resposta git_name 2>/dev/null)"; GIT_NAME="${GIT_NAME:-StayneDev}"
  GIT_EMAIL="$(resposta git_email 2>/dev/null)"; GIT_EMAIL="${GIT_EMAIL:-makalyster.devops@gmail.com}"
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global init.defaultBranch main

  if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$HOME/.ssh/id_ed25519" -N ""
    eval "$(ssh-agent -s)"
    ssh-add "$HOME/.ssh/id_ed25519"
  fi

  PUB_KEY=$(cat "$HOME/.ssh/id_ed25519.pub")
  copy_to_clipboard "$PUB_KEY"

  echo ""
  echo "  ============================================================"
  echo "  CHAVE SSH GERADA (ja copiada para o clipboard):"
  echo "  ============================================================"
  echo "  $PUB_KEY"
  echo "  ============================================================"

  # Abre GitHub no browser para adicionar a chave (so se houver display)
  [ -n "$DISPLAY" ] && xdg-open "https://github.com/settings/keys" 2>/dev/null &

  pause "Cole a chave SSH no GitHub (github.com/settings/keys) e clique em 'Add SSH key'"

  # Testa conexao
  echo "  Testando conexao SSH com GitHub..."
  if ssh -T git@github.com -o StrictHostKeyChecking=no 2>&1 | grep -q "successfully authenticated"; then
    echo "  [OK] GitHub autenticado com sucesso."
  else
    echo "  [AVISO] Conexao nao confirmada. Verifique se a chave foi adicionada corretamente."
  fi
}

# =============================================================================
# 7. FIREFOX — privacidade, segurança e Bitwarden
# =============================================================================

# Detecta qual Firefox esta disponivel e retorna o comando para abri-lo
_firefox_cmd() {
  if command -v firefox &>/dev/null; then
    echo "firefox"
  elif flatpak list --app 2>/dev/null | grep -q org.mozilla.firefox; then
    echo "flatpak run org.mozilla.firefox"
  else
    echo ""
  fi
}

# Detecta o diretorio do perfil ativo (nativo primeiro, Flatpak como fallback)
_firefox_profile() {
  local profile=""
  if [ -d "$HOME/.mozilla/firefox" ]; then
    profile=$(find "$HOME/.mozilla/firefox" -maxdepth 1 -name "*.default*" -type d | head -1)
  fi
  if [ -z "$profile" ] && [ -d "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox" ]; then
    profile=$(find "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox" -maxdepth 1 -name "*.default*" -type d | head -1)
  fi
  # Ubuntu 24.04: firefox nativo é SNAP e o perfil mora em ~/snap (achado do dev-QA #25)
  if [ -z "$profile" ] && [ -d "$HOME/snap/firefox/common/.mozilla/firefox" ]; then
    profile=$(find "$HOME/snap/firefox/common/.mozilla/firefox" -maxdepth 1 -name "*.default*" -type d | head -1)
  fi
  echo "$profile"
}

setup_firefox() {
  echo -e "\n[firefox] Configurando Firefox..."

  local FF_CMD
  FF_CMD=$(_firefox_cmd)

  if [ -z "$FF_CMD" ]; then
    echo "  [ERRO] Firefox nao encontrado (nativo nem Flatpak)."
    echo "         Instale o Firefox e re-execute: bash setup.sh --firefox"
    return 1
  fi

  # Se perfil nao existe, abre Firefox para criar e aguarda
  local FIREFOX_PROFILE
  FIREFOX_PROFILE=$(_firefox_profile)
  if [ -z "$FIREFOX_PROFILE" ]; then
    echo "  [INFO] Perfil nao encontrado — abrindo Firefox para criacao inicial..."
    $FF_CMD &>/dev/null &
    pause "Firefox aberto. Aguarde carregar completamente e depois FECHE-O para continuar"
    # snap firefox demora no primeiro launch (seed) — espera ATIVA pelo perfil,
    # ate 90s, em vez de confiar no timing do ENTER (achado do dev-QA #25)
    local tent=0
    FIREFOX_PROFILE=$(_firefox_profile)
    while [ -z "$FIREFOX_PROFILE" ] && [ $tent -lt 45 ]; do
      sleep 2; tent=$((tent+1))
      FIREFOX_PROFILE=$(_firefox_profile)
    done
  fi

  if [ -z "$FIREFOX_PROFILE" ]; then
    echo "  [ERRO] Perfil ainda nao encontrado. Abra o Firefox manualmente e re-execute: bash setup.sh --firefox"
    return 1
  fi

  echo "  [INFO] Perfil: $FIREFOX_PROFILE"

  # --- user.js — perfil de privacidade e seguranca ---
  # SCRIPT_DIR e DOTFILES_RAW vêm do topo, já resolvidos para o ref corrente.
  if [ -f "$SCRIPT_DIR/firefox-user.js" ]; then
    cp "$SCRIPT_DIR/firefox-user.js" "$FIREFOX_PROFILE/user.js"
  else
    curl -fsSL "$DOTFILES_RAW/firefox-user.js" -o "$FIREFOX_PROFILE/user.js"
  fi
  echo "  [OK] user.js aplicado (privacidade + seguranca)."

  # --- Bitwarden — instala XPI direto no perfil (sem polkit/policies) ---
  local BITWARDEN_ID="{446900e4-71c2-419f-a6a7-df9c091e268b}"
  local BITWARDEN_URL="https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi"
  local EXT_DIR="$FIREFOX_PROFILE/extensions"
  mkdir -p "$EXT_DIR"
  echo "  Baixando Bitwarden..."
  if curl -fsSL "$BITWARDEN_URL" -o "$EXT_DIR/$BITWARDEN_ID.xpi"; then
    echo "  [OK] Bitwarden instalado no perfil — sera ativado ao abrir o Firefox."
  else
    echo "  [AVISO] Falha ao baixar Bitwarden. Sera aberto o link de instalacao no login-firefox."
  fi

  echo ""
  echo "  ============================================================"
  echo "  Firefox configurado. Proximos passos:"
  echo "  1. Execute: bash setup.sh --login-firefox"
  echo "  2. Bitwarden abrira automaticamente — faca login"
  echo "  3. Importe suas configuracoes/cofre se necessario"
  echo "  4. So entao execute: bash setup.sh --github"
  echo "  ============================================================"
}

# =============================================================================
# 8. SSHPILOT
# =============================================================================
install_sshpilot() {
  echo -e "\n[sshpilot] Instalando sshpilot..."
  case $DISTRO in
    arch)
      # Arch tem libadwaita atualizada — instala via AUR
      yay -S --noconfirm sshpilot
      ;;
    debian|fedora)
      # Debian Bookworm tem libadwaita 1.2.x (requer >= 1.4) — usa Flatpak autocontido
      # Fedora: Flatpak evita conflitos de versao de lib entre releases
      sudo flatpak install -y flathub io.github.mfat.sshpilot
      ;;
  esac
  echo "  [OK] sshpilot instalado."
}

# =============================================================================
# 9. LOGINS RUNTIME — Discord, Steam, Tailscale
# =============================================================================
# =============================================================================
# UTILITARIO — remover Firefox nativo e instalar Flatpak
# =============================================================================
remove_native_firefox() {
  echo -e "\n[firefox] Removendo Firefox nativo e instalando Flatpak..."
  case $DISTRO in
    arch)
      sudo pacman -Rns --noconfirm firefox 2>/dev/null || echo "  [INFO] firefox nativo nao encontrado via pacman."
      ;;
    debian)
      sudo apt remove -y --purge firefox-esr firefox 2>/dev/null || true
      sudo apt autoremove -y
      ;;
    fedora)
      sudo dnf remove -y firefox 2>/dev/null || true
      ;;
  esac
  # Remove perfil nativo (backup antes)
  if [ -d "$HOME/.mozilla/firefox" ]; then
    mv "$HOME/.mozilla/firefox" "$HOME/.mozilla/firefox.bak.$(date +%Y%m%d%H%M%S)"
    echo "  [OK] Perfil nativo movido para backup em ~/.mozilla/firefox.bak.*"
  fi
  flatpak install -y flathub org.mozilla.firefox
  echo "  [OK] Firefox Flatpak instalado. Execute --firefox para configurar."
}

login_firefox() {
  echo -e "\n[Firefox] Abrindo Firefox para login no Bitwarden..."
  local FF_CMD
  FF_CMD=$(_firefox_cmd)
  if [ -z "$FF_CMD" ]; then
    echo "  [ERRO] Firefox nao encontrado. Instale e re-execute."
    return 1
  fi

  local BITWARDEN_ID="{446900e4-71c2-419f-a6a7-df9c091e268b}"
  local BITWARDEN_AMO="https://addons.mozilla.org/pt-BR/firefox/addon/bitwarden-password-manager/"
  local FIREFOX_PROFILE
  FIREFOX_PROFILE=$(_firefox_profile)

  # Verifica se XPI foi instalado no perfil
  if [ -n "$FIREFOX_PROFILE" ] && [ -f "$FIREFOX_PROFILE/extensions/$BITWARDEN_ID.xpi" ]; then
    # XPI presente — abre Firefox normalmente, extensao sera ativada
    $FF_CMD &>/dev/null &
    echo ""
    echo "  ============================================================"
    echo "  Firefox aberto. O icone do Bitwarden aparecera na toolbar."
    echo ""
    echo "  O QUE FAZER:"
    echo "  1. Clique no icone do Bitwarden na toolbar"
    echo "  2. Clique em 'Criar conta' ou 'Fazer login'"
    echo "  3. Entre com seu email e senha mestre"
    echo "  4. Se o cofre nao sincronizar, clique em 'Sincronizar cofre'"
    echo "  5. Fixe o icone: clique no quebra-cabeca (extensoes) > Bitwarden > fixar na toolbar"
    echo "  ============================================================"
  else
    # XPI ausente — abre direto na pagina de instalacao (1 clique)
    $FF_CMD "$BITWARDEN_AMO" &>/dev/null &
    echo ""
    echo "  ============================================================"
    echo "  Firefox aberto na pagina do Bitwarden na AMO."
    echo ""
    echo "  O QUE FAZER:"
    echo "  1. Clique em 'Adicionar ao Firefox' e confirme a permissao"
    echo "  2. Clique no icone do Bitwarden que apareceu na toolbar"
    echo "  3. Entre com seu email e senha mestre"
    echo "  4. Se o cofre nao sincronizar, clique em 'Sincronizar cofre'"
    echo "  5. Fixe o icone: clique no quebra-cabeca (extensoes) > Bitwarden > fixar na toolbar"
    echo "  ============================================================"
  fi

  pause "Pressione ENTER quando estiver logado no Bitwarden"
}

login_discord() {
  echo -e "\n[Discord] Abrindo Discord para login..."
  flatpak run com.discordapp.Discord &>/dev/null &
  pause "Faca login no Discord e feche-o (ou minimize) quando terminar"
}

login_steam() {
  echo -e "\n[Steam] Abrindo Steam para login..."
  flatpak run com.valvesoftware.Steam &>/dev/null &
  pause "Faca login no Steam e feche-o (ou minimize) quando terminar"
}

login_tailscale() {
  echo -e "\n[Tailscale] Autenticacao via auth key..."
  echo ""
  local FF_CMD; FF_CMD=$(_firefox_cmd)
  [ -n "$DISPLAY" ] && [ -n "$FF_CMD" ] && $FF_CMD "https://login.tailscale.com/admin/machines/new-linux" &>/dev/null &
  echo "  ============================================================"
  echo "  1. Acesse: https://login.tailscale.com/admin/machines/new-linux"
  echo "  2. Clique em 'Generate auth key'"
  echo "  3. Marque 'Reusable' se quiser usar em mais de uma maquina"
  echo "  4. Cole a chave abaixo (formato: tskey-auth-...)"
  echo "  ============================================================"
  read -rp "  Auth key: " TAILSCALE_KEY
  if [ -n "$TAILSCALE_KEY" ]; then
    sudo tailscale up --authkey="$TAILSCALE_KEY"
    if tailscale status &>/dev/null; then
      echo "  [OK] Tailscale conectado."
    else
      echo "  [AVISO] Tailscale nao confirmado. Verifique a chave e tente: sudo tailscale up --authkey=<key>"
    fi
  else
    echo "  [AVISO] Nenhuma chave informada. Execute manualmente: sudo tailscale up --authkey=<key>"
  fi
}

login_claude() {
  echo -e "\n[Claude Code] Iniciando login..."
  if ! command -v claude &>/dev/null; then
    echo "  [AVISO] Claude Code nao encontrado. Instale primeiro com --node."
    return 1
  fi
  echo ""
  echo "  ============================================================"
  echo "  Sera aberto o fluxo de autenticacao no browser."
  echo "  >> Faca login com sua conta Anthropic"
  echo "  >> Autorize o acesso quando solicitado"
  echo "  ============================================================"
  claude --dangerously-skip-permissions /login 2>/dev/null || true
  pause "Pressione ENTER quando o login estiver concluido"
}

runtime_logins() {
  login_discord
  login_steam
  login_tailscale
  login_claude
}

# =============================================================================
# 10. VSCODE — extensões e settings
# =============================================================================
setup_vscode() {
  echo -e "\n[vscode] Aplicando settings e instalando extensões..."

  # SCRIPT_DIR e DOTFILES_RAW vêm do topo, já resolvidos para o ref corrente.
  VSCODE_SETTINGS_DIR="$HOME/.config/Code/User"
  mkdir -p "$VSCODE_SETTINGS_DIR"

  # settings.json — local ou fallback via curl
  if [ -f "$SCRIPT_DIR/vscode-settings.json" ]; then
    cp "$SCRIPT_DIR/vscode-settings.json" "$VSCODE_SETTINGS_DIR/settings.json"
  else
    curl -fsSL "$DOTFILES_RAW/vscode-settings.json" -o "$VSCODE_SETTINGS_DIR/settings.json"
  fi
  echo "  [OK] Settings aplicados."

  # vscode-extensions.txt — local ou fallback via curl
  EXTENSIONS_FILE="$SCRIPT_DIR/vscode-extensions.txt"
  if [ ! -f "$EXTENSIONS_FILE" ]; then
    EXTENSIONS_FILE="/tmp/vscode-extensions.txt"
    curl -fsSL "$DOTFILES_RAW/vscode-extensions.txt" -o "$EXTENSIONS_FILE"
  fi

  if ! command -v code &>/dev/null; then
    echo "  [AVISO] VSCode não encontrado. Instale primeiro com --base."
    return
  fi
  echo "  Instalando extensões..."
  while IFS= read -r ext; do
    [[ -z "$ext" || "$ext" == \#* ]] && continue
    code --install-extension "$ext" --force 2>/dev/null && echo "  [OK] $ext" || echo "  [ERRO] $ext"
  done < "$EXTENSIONS_FILE"
  echo "  [OK] Extensões instaladas."
}

# =============================================================================
# 11. CLAUDE CONFIG (skills, settings — repo dedicado)
# =============================================================================
install_claude_config() {
  echo -e "\n[fechar] Configurando Claude Code (o par acervo + maquinaria)..."
  local ACERVO_DIR="$HOME/repos/orquestrador-normativo-agente-acervo"
  local MOTOR_DIR="$HOME/repos/orquestrador-normativo-agente-maquinaria"
  # repos privados — clone via SSH (requer --github feito antes)
  mkdir -p "$HOME/repos"
  if [ ! -d "$ACERVO_DIR/.git" ]; then
    git clone git@github.com:StayneDev/orquestrador-normativo-agente-acervo.git "$ACERVO_DIR"
  fi
  if [ ! -d "$MOTOR_DIR/.git" ]; then
    git clone git@github.com:StayneDev/orquestrador-normativo-agente-maquinaria.git "$MOTOR_DIR"
  fi
  # o install mora na MAQUINARIA e instala o par (ADR-20260730-estratos-e-extracao)
  bash "$MOTOR_DIR/install.sh"
  echo "  [OK] Claude config (par) instalado."
}

# =============================================================================
# FASES (U15) — provisionar → configurar → autenticar → fechar
# =============================================================================
# A passagem entre fases é VERIFICADA, nunca comentário: cada fase abre com o
# gate que prova a anterior, lendo o estado real da máquina (não a memória de
# execução — "rodei" não é "está"). Gate reprovado recusa na entrada e CONDUZ:
# diz exatamente o comando que resolve. Decidido na antessala
# (docs/Decisões/ADR-20260801-antessala-bootstrap-do-par-e-da-infra.md, issue #20).

gate_provisionado() {
  local faltas=()
  local b
  for b in git curl zsh flatpak; do
    command -v "$b" &>/dev/null || faltas+=("$b")
  done
  if [ ${#faltas[@]} -gt 0 ]; then
    echo "[gate] provisionar incompleto — faltam: ${faltas[*]}"
    echo "[gate] rode antes: bash setup.sh --fase provisionar"
    return 1
  fi
}

gate_configurado() {
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "[gate] configurar incompleto — terminal não configurado (oh-my-zsh ausente)"
    echo "[gate] rode antes: bash setup.sh --fase configurar"
    return 1
  fi
}

gate_autenticado() {
  if ! ssh -T git@github.com -o StrictHostKeyChecking=no -o BatchMode=yes 2>&1 | grep -q "successfully authenticated"; then
    echo "[gate] autenticar incompleto — GitHub não responde à chave SSH desta máquina"
    echo "[gate] rode antes: bash setup.sh --fase autenticar"
    return 1
  fi
}

fase_provisionar() {
  echo -e "\n══════ FASE 1/4 — PROVISIONAR (tudo que é público) ══════"
  detect_distro
  install_base
  install_flatpak_apps
  install_java
  install_node_and_claude
  install_sshpilot
}

fase_configurar() {
  gate_provisionado || return 1
  echo -e "\n══════ FASE 2/4 — CONFIGURAR ══════"
  setup_terminal
  setup_vscode
  setup_firefox
}

fase_autenticar() {
  gate_configurado || return 1
  echo -e "\n══════ FASE 3/4 — AUTENTICAR (interativa por natureza) ══════"
  login_firefox          # Bitwarden primeiro: é o cofre de onde o resto sai
  setup_git_ssh          # chave SSH + GitHub — destrava os clones privados
  login_tailscale
  login_claude
}

fase_fechar() {
  gate_autenticado || return 1
  echo -e "\n══════ FASE 4/4 — FECHAR (clones privados + verificação) ══════"
  install_claude_config  # clona o par e roda o install.sh do motor, que verifica
  echo ""
  echo "============================================================"
  echo "  FASES CONCLUÍDAS"
  echo "  Logins de apps pessoais (à parte, por perfil): --discord --steam"
  echo "  Reinicie o terminal para aplicar o zsh."
  echo "============================================================"
}

rodar_fase() {
  case "$1" in
    provisionar) fase_provisionar ;;
    configurar)  fase_configurar ;;
    autenticar)  fase_autenticar ;;
    fechar)      fase_fechar ;;
    *) echo "Fase desconhecida: $1 (use: provisionar | configurar | autenticar | fechar)"; return 1 ;;
  esac
}

# =============================================================================
# AJUDA
# =============================================================================
show_help() {
  echo ""
  echo "Uso: bash setup.sh [opcao]"
  echo ""
  echo "  (sem opcao)       Menu de perfil (pergunta UMA vez, grava respostas) + 4 fases"
  echo ""
  echo "  Perfis (manifesto em perfis/*.perfil; composicao: perfil = minimo + camada):"
  echo "    --perfil <nome>      headless: minimo | pessoal | profissional | infra"
  echo "    --conferir [nome]    conferencia declarado x real do perfil"
  echo ""
  echo "  Fases (a passagem e verificada — fase sem pre-requisito recusa e conduz):"
  echo "    --fase provisionar   1/4: tudo que e publico (base, flatpak, java, node, sshpilot)"
  echo "    --fase configurar    2/4: terminal, vscode, firefox (exige provisionar)"
  echo "    --fase autenticar    3/4: bitwarden, ssh/github, tailscale, claude (exige configurar)"
  echo "    --fase fechar        4/4: clones privados do par + verificacao (exige autenticar)"
  echo ""
  echo "  Instalacao:"
  echo "    --base          Pacotes base (git, curl, zsh, vscode...)"
  echo "    --flatpak       Apps Flatpak (Discord, Steam, Firefox)"
  echo "    --java          JDK 21"
  echo "    --node          nvm + Node LTS + Claude Code"
  echo "    --sshpilot      sshpilot (AUR / APT / COPR)"
  echo "    --vscode        Settings e extensões do VSCode"
  echo "    --claude        Claude skills, settings e sync automático"
  echo ""
  echo "  Configuracao:"
  echo "    --terminal      Zsh + Oh My Zsh + tema bira"
  echo "    --firefox       Firefox privacidade + Bitwarden (fazer antes de --github)"
  echo "    --github        Git config + chave SSH + adicionar no GitHub (requer Bitwarden)"
  echo ""
  echo "  Logins:"
  echo "    --login-firefox        Abrir Firefox para login + Bitwarden
    --remove-native-firefox Remover Firefox nativo e instalar via Flatpak"
  echo "    --discord       Abrir Discord para login"
  echo "    --steam         Abrir Steam para login"
  echo "    --tailscale     Autenticar Tailscale"
  echo "    --logins        Todos os logins em sequencia (discord, steam, tailscale)"
  echo ""
}

# =============================================================================
# EXECUCAO
# =============================================================================
# Guard de source: os testes (testes/fases.sh) carregam as funções com `source`
# sem disparar o dispatch — executar direto continua funcionando igual.
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return 0 2>/dev/null || true
fi

case "$1" in
  --fase)       rodar_fase "$2" ;;
  --perfil)     rodar_perfil "$2" ;;   # headless: com respostas gravadas, não pergunta nada
  --conferir)   conferir_perfil "${2:-$(resposta perfil)}" ;;
  --base)       detect_distro; install_base ;;
  --flatpak)    install_flatpak_apps ;;
  --java)       detect_distro; install_java ;;
  --node)       install_node_and_claude ;;
  --sshpilot)   detect_distro; install_sshpilot ;;
  --terminal)   setup_terminal ;;
  --github)     setup_git_ssh ;;
  --firefox)    setup_firefox ;;
  --login-firefox) login_firefox ;;
  --remove-native-firefox) detect_distro; remove_native_firefox ;;
  --discord)    login_discord ;;
  --steam)      login_steam ;;
  --tailscale)  login_tailscale ;;
  --logins)     runtime_logins ;;
  --vscode)     setup_vscode ;;
  --claude)     install_claude_config ;;
  --help|-h)    show_help ;;
  "")
    # Interativo UMA VEZ (#22): o menu escolhe o perfil e colhe as divergentes
    # no início; grava nas respostas; o resto roda sozinho pelas 4 fases com
    # gates (#20). Re-execução lê as respostas e não pergunta (U8).
    PERFIL_ESCOLHIDO=$(menu_perfil) || exit 1
    rodar_perfil "$PERFIL_ESCOLHIDO"
    ;;
  *)
    echo "Opcao desconhecida: $1"
    show_help
    exit 1
    ;;
esac
