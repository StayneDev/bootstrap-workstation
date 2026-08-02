#!/usr/bin/env bash
# testes/perfis.sh — bateria dos manifestos, respostas, menu e conferência (#21 #22 #24).
set -u
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$AQUI/../setup.sh"
SB=$(mktemp -d) || exit 1
trap 'rm -rf "$SB"' EXIT
passou=0; falhou=0
ok()   { echo "  [ok]    $1"; passou=$((passou+1)); }
FALHA(){ echo "  [FALHA] $1"; falhou=$((falhou+1)); }

carrega() { # ambiente isolado por caso
  HOME="$SB/home" RESPOSTAS="$SB/home/.config/bw/respostas" bash -c "source '$SETUP'; $1" 2>&1
}
mkdir -p "$SB/home"

# ── 1. herança resolve na ordem e deduplica ──────────────────────────────────
saida=$(carrega "resolver_perfil pessoal")
if echo "$saida" | head -1 | grep -q 'provisionar base' && echo "$saida" | grep -q 'provisionar discord' \
   && [ "$(echo "$saida" | sort | uniq -d | wc -l)" -eq 0 ]; then
  ok "pessoal herda minimo (base primeiro), soma a camada, sem duplicata"
else
  FALHA "resolução do pessoal errada: $saida"
fi

# ── 2. perfil inexistente recusa nomeando os que existem ─────────────────────
saida=$(carrega "resolver_perfil banana"); rc=$?
[ $rc -ne 0 ] && echo "$saida" | grep -q 'não existe' && echo "$saida" | grep -q 'minimo' \
  && ok "perfil inexistente recusa e lista os disponíveis" \
  || FALHA "perfil inexistente não recusou/conduziu (rc=$rc): $saida"

# ── 3. divergentes herdam (pessoal carrega git_name do minimo) ───────────────
saida=$(carrega "divergentes_do_perfil pessoal")
echo "$saida" | grep -qx 'git_name' && ok "divergentes herdam pela cadeia" \
  || FALHA "divergentes não herdaram: $saida"

# ── 4. respostas: grava, lê, re-execução não pergunta ────────────────────────
saida=$(carrega "grava_resposta git_name Fulano; resposta git_name")
echo "$saida" | grep -qx 'Fulano' && ok "resposta grava e lê" || FALHA "respostas: $saida"

# ── 5. sobrescrita reporta alto ──────────────────────────────────────────────
saida=$(carrega "grava_resposta k v1 >/dev/null; grava_resposta k v2")
echo "$saida" | grep -q "sobrescrevendo k: 'v1' → 'v2'" && ok "sobrescrita de resposta reporta alto" \
  || FALHA "sobrescrita silenciosa: $saida"

# ── 6. menu grava a escolha; segunda chamada NÃO pergunta (U8) ───────────────
saida=$(HOME="$SB/home" RESPOSTAS="$SB/home/.config/bw/respostas" bash -c "source '$SETUP'; echo 1 | menu_perfil >/dev/null; menu_perfil" 2>&1)
if echo "$saida" | grep -q 'não pergunto de novo' && echo "$saida" | tail -1 | grep -qx 'infra'; then
  ok "menu pergunta uma vez; re-execução lê as respostas (perfil infra=1º alfabético)"
else
  FALHA "menu re-perguntou ou escolheu errado: $saida"
fi

# ── 7. menu recusa escolha inválida ──────────────────────────────────────────
saida=$(HOME="$SB/h2" RESPOSTAS="$SB/h2/r" bash -c "mkdir -p $SB/h2; source '$SETUP'; echo 99 | menu_perfil"); rc=$?
[ $rc -ne 0 ] && ok "menu recusa escolha fora da lista" || FALHA "menu aceitou 99 (rc=$rc)"

# ── 8. conferência: divergência nomeada e exit 1 (HOME vazio não tem nada) ───
saida=$(HOME="$SB/home-vazio" bash -c "mkdir -p $SB/home-vazio; source '$SETUP'; PATH=/usr/bin:/bin; conferir_perfil minimo"); rc=$?
if [ $rc -ne 0 ] && echo "$saida" | grep -q 'DIVERGE.*terminal' && echo "$saida" | grep -q 'divergência'; then
  ok "conferência acusa divergência nomeada e sai 1"
else
  FALHA "conferência não acusou (rc=$rc): $saida"
fi

# ── 9. conferência: passo satisfeito diz ok (terminal com HOME preparado) ────
# O `getent` é dublado porque a prova do terminal olha o shell de LOGIN, que é
# fato da máquina que roda o teste — sem o dublê o caso passaria ou falharia
# conforme o shell de quem executa, e teste que depende do host não prova nada.
mkdir -p "$SB/home-conf/.oh-my-zsh" && touch "$SB/home-conf/.zshrc"
mkdir -p "$SB/bin-zsh"
cat > "$SB/bin-zsh/getent" <<EOF
#!/bin/sh
echo "\$2:x:1000:1000::/home/\$2:$(command -v zsh || echo /usr/bin/zsh)"
EOF
chmod +x "$SB/bin-zsh/getent"
saida=$(HOME="$SB/home-conf" PATH="$SB/bin-zsh:$PATH" bash -c "source '$SETUP'; conferir_perfil minimo" 2>&1)
echo "$saida" | grep -q '\[ok\].*terminal' && ok "conferência constata o que existe" \
  || FALHA "conferência não viu o terminal presente: $saida"

# ── 9b. shell de login em bash DIVERGE, mesmo com oh-my-zsh e .zshrc no lugar ─
# É o caso que faltava: o chsh falhava por PAM, os dois arquivos existiam e a
# conferência dizia "ok" com o operador ainda em bash (aceite #26).
mkdir -p "$SB/bin-bash"
cat > "$SB/bin-bash/getent" <<'EOF'
#!/bin/sh
echo "$2:x:1000:1000::/home/$2:/bin/bash"
EOF
chmod +x "$SB/bin-bash/getent"
saida=$(HOME="$SB/home-conf" PATH="$SB/bin-bash:$PATH" bash -c "source '$SETUP'; conferir_perfil minimo" 2>&1)
echo "$saida" | grep -q 'DIVERGE.*terminal' \
  && ok "shell de login em bash diverge, apesar de oh-my-zsh e .zshrc presentes" \
  || FALHA "conferência aprovou terminal com shell de login errado: $saida"

# ── 9c. REGRESSÃO: prova que lê stdin não pode truncar a conferência ──────────
# O `ssh -T` da prova do git_ssh comia o stdin do `while read` que percorria os
# passos: 6 de 14 conferidos no `pessoal` e ainda assim "confere: tudo".
# Conferência cega é pior que vermelha — aprova o que não olhou.
saida=$(HOME="$SB/h-reg" bash -c "mkdir -p '$SB/h-reg'; source '$SETUP';
  prova_passo(){ [ \"\$1\" = git_ssh ] && cat >/dev/null; return 0; }
  conferir_perfil pessoal" </dev/null 2>&1)
declarados=$(carrega "resolver_perfil pessoal" | grep -c .)
conferidos=$(echo "$saida" | grep -c '^  \[ok\]')
if [ "$conferidos" -eq "$declarados" ] && echo "$saida" | grep -q '\[ok\].*tailscale'; then
  ok "prova que consome stdin não trunca a conferência ($conferidos de $declarados)"
else
  FALHA "conferência truncou: $conferidos de $declarados conferidos"
fi

# ── 10. passo desconhecido no manifesto recusa ───────────────────────────────
saida=$(carrega "executa_passo inexistente"); rc=$?
[ $rc -ne 0 ] && echo "$saida" | grep -q 'passo desconhecido' && ok "passo desconhecido recusa nomeando" \
  || FALHA "passo desconhecido passou (rc=$rc): $saida"

echo ""
echo "── perfis: $passou ok · $falhou falha(s) ──"
[ $falhou -eq 0 ] || exit 1
