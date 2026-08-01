#!/usr/bin/env bash
# testes/fases.sh — bateria da camada de fases do setup.sh (issue #20).
#
# A regra de armação prova só metade: passar no que deve passar. Cada gate aqui
# tem também o caso NEGATIVO — recusando o que deve recusar, com a condução
# (a mensagem que diz o comando que resolve). Persistida em arquivo porque
# bateria que não fica em arquivo não existe (lição da maquinaria, 2026-08-01).
#
# Roda em sandbox: HOME e PATH falsos por caso. Nada toca a máquina real.
set -u

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$AQUI/../setup.sh"
SB=$(mktemp -d) || exit 1
trap 'rm -rf "$SB"' EXIT

passou=0; falhou=0
ok()   { echo "  [ok]    $1"; passou=$((passou+1)); }
FALHA(){ echo "  [FALHA] $1"; falhou=$((falhou+1)); }

# shim com os binários básicos que os casos positivos precisam
mkdir -p "$SB/shim"
for b in git curl zsh flatpak; do
  printf '#!/bin/bash\nexit 0\n' > "$SB/shim/$b" && chmod +x "$SB/shim/$b"
done
# ssh que autentica (positivo) e ssh que nega (negativo)
mkdir -p "$SB/ssh-ok" "$SB/ssh-nao"
printf '#!/bin/bash\necho "Hi! You have successfully authenticated"\nexit 1\n' > "$SB/ssh-ok/ssh"
printf '#!/bin/bash\necho "Permission denied (publickey)"\nexit 255\n' > "$SB/ssh-nao/ssh"
chmod +x "$SB/ssh-ok/ssh" "$SB/ssh-nao/ssh"

# ── 1. source não dispara o dispatch (guard) ─────────────────────────────────
saida=$(cd "$SB" && bash -c "source '$SETUP' 2>&1; echo GUARD_OK")
if echo "$saida" | grep -q GUARD_OK && ! echo "$saida" | grep -q 'FASE 1/4'; then
  ok "source do setup.sh não executa nada (guard de dispatch)"
else
  FALHA "source disparou execução — guard furou: $saida"
fi

# ── 2. gate_provisionado NEGATIVO: PATH vazio recusa e conduz ────────────────
saida=$(HOME="$SB/home-vazio" bash -c "source '$SETUP'; PATH='$SB/vazio'; gate_provisionado" 2>&1); rc=$?
if [ $rc -ne 0 ] && echo "$saida" | grep -q 'provisionar incompleto' && echo "$saida" | grep -q -- '--fase provisionar'; then
  ok "gate_provisionado recusa sem binários e conduz ao comando"
else
  FALHA "gate_provisionado não recusou/conduziu (rc=$rc): $saida"
fi

# ── 3. gate_provisionado POSITIVO: com os binários, passa ────────────────────
saida=$(bash -c "source '$SETUP'; PATH='$SB/shim:/usr/bin:/bin'; gate_provisionado" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "gate_provisionado passa com os binários presentes" \
             || FALHA "gate_provisionado recusou o que devia passar (rc=$rc): $saida"

# ── 4. gate_configurado NEGATIVO: HOME sem oh-my-zsh recusa e conduz ─────────
mkdir -p "$SB/home-vazio"
saida=$(bash -c "HOME='$SB/home-vazio'; source '$SETUP'; gate_configurado" 2>&1); rc=$?
if [ $rc -ne 0 ] && echo "$saida" | grep -q 'configurar incompleto' && echo "$saida" | grep -q -- '--fase configurar'; then
  ok "gate_configurado recusa sem terminal configurado e conduz"
else
  FALHA "gate_configurado não recusou/conduziu (rc=$rc): $saida"
fi

# ── 5. gate_configurado POSITIVO ─────────────────────────────────────────────
mkdir -p "$SB/home-conf/.oh-my-zsh"
saida=$(bash -c "HOME='$SB/home-conf'; source '$SETUP'; gate_configurado" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "gate_configurado passa com oh-my-zsh presente" \
             || FALHA "gate_configurado recusou o que devia passar (rc=$rc): $saida"

# ── 6. gate_autenticado POSITIVO: ssh autenticando abre ──────────────────────
saida=$(bash -c "source '$SETUP'; PATH='$SB/ssh-ok:/usr/bin:/bin'; gate_autenticado" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "gate_autenticado passa quando o GitHub responde à chave" \
             || FALHA "gate_autenticado recusou auth válida (rc=$rc): $saida"

# ── 7. gate_autenticado NEGATIVO: ssh negando recusa e conduz ────────────────
saida=$(bash -c "source '$SETUP'; PATH='$SB/ssh-nao:/usr/bin:/bin'; gate_autenticado" 2>&1); rc=$?
if [ $rc -ne 0 ] && echo "$saida" | grep -q 'autenticar incompleto' && echo "$saida" | grep -q -- '--fase autenticar'; then
  ok "gate_autenticado recusa sem auth e conduz"
else
  FALHA "gate_autenticado não recusou/conduziu (rc=$rc): $saida"
fi

# ── 8. fase com pré-requisito reprovado recusa NA ENTRADA (não executa nada) ─
mkdir -p "$SB/home-fase"
saida=$(bash -c "HOME='$SB/home-fase'; source '$SETUP'; PATH='$SB/vazio'; fase_configurar" 2>&1); rc=$?
if [ $rc -ne 0 ] && [ ! -f "$SB/home-fase/.zshrc" ]; then
  ok "fase_configurar sem provisionar recusa na entrada — setup_terminal nunca rodou"
else
  FALHA "fase_configurar executou com gate reprovado (rc=$rc, zshrc=$([ -f "$SB/home-fase/.zshrc" ] && echo existe))"
fi

# ── 9. fase desconhecida recusa ──────────────────────────────────────────────
saida=$(bash -c "source '$SETUP'; rodar_fase inexistente" 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$saida" | grep -q 'Fase desconhecida' \
  && ok "rodar_fase recusa fase desconhecida" \
  || FALHA "rodar_fase aceitou fase inexistente (rc=$rc): $saida"

echo ""
echo "── fases: $passou ok · $falhou falha(s) ──"
[ $falhou -eq 0 ] || exit 1
