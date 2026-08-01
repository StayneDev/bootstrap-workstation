---
type: adr
status: proposto
data: 2026-08-01
updated: 2026-08-01
tags: [adr, antessala, bootstrap]
---

# ADR-20260801 — Antessala: bootstrap reproduzível do par e da infra

**Este nó é a antessala em forma de artefato** — o desejo entra quebrado e é empurrado contra o real até sair um *como* que sobrevive. Está `proposto` e mutável; fica apto quando responder as quatro perguntas (*o que se quer · contra o que se bateu · o que sobreviveu · por que não os outros*), e **a passagem antessala → esteira é leitura do operador**, não deste texto. Mora no nº 3 porque estação vem antes de infra — é dela que o provisionamento roda — e porque o nº 3 é a metade que já meio-funciona; se a metade de infra amadurecer em ritmo próprio, **gradua** para ADR no `bootstrap-infra`, citando este.

Sem `k` nem `escopo`: são campos da propagação do vault; aqui a esteira é a do produto. `Contexto → k` do vault equivale aqui a: isto é o **`destrava:`** do [[ADR-20260730-estratos-e-extracao]] — a produção que o episódio de amadurecimento prometeu destravar — e a fome (produto × vault) está cobrando exatamente este retorno.

## O que se quer (o desejo, limpo de premissas)

1. **Máquina nova vira estação do operador num comando**: clona o par (`orquestrador-normativo-agente-{maquinaria,acervo}`), instala ganchos, symlinks e travas, e **verifica** — idempotente (U8), falha visível (U2), zero passo manual não documentado.
2. **Infra nova (LXC, cluster, PBS) nasce do repo nº 4 sob a doutrina do acervo** — a doutrina desce ao provisionador, nunca ao provisionado (decidido no estratos: a LXC não carrega Charter; quem provisiona lê e aplica).
3. **Reproduzível de verdade**: rodar duas vezes dá o mesmo resultado e a segunda diz "nada a fazer"; o que falha, falha dizendo o quê.

Premissa **removida de propósito**: o *como* (shell puro? Ansible? cloud-init?) não entra no desejo — "quero um container **no proxmox**" foi o exemplo canônico de desejo contaminado. O [[ADR-20260725-ferramentas-infra]] decidiu adoção faseada (Ansible depois; TF/k8s/Zabbix não) — se essa decisão sobrevive a este confronto é pergunta do confronto, não premissa da entrada.

## Contra o que se bateu (medido em 2026-08-01)

1. **O nº 3 está meio-vivo e nunca provado inteiro.** O `machine/setup.sh` hoje clona o par e chama o `install.sh` do motor (consertado no dia do corte). Mas: o `install.sh` **do par** nunca rodou em máquina limpa (a versão pré-corte passou 5/5 na VM 303 em 30/07 — veredito aberto nas Dívidas do acervo); e o setup inteiro (login, git config, SSH, Tailscale) **nunca** teve teste de máquina limpa — é ele quem clona o par, e é a metade declarada como não-coberta pelo próprio install.
2. **O nº 4 é um saco misto, e a triagem já está feita** (estratos, 31/07): dos 34 arquivos, 25 são provisionamento legítimo; 1 é doutrina (`lxc-standards.md` → `dominios/Homelab` do acervo); 2 são estado morto por U4 (`CLAUDE.md` com tabela LXC/IP/status, `mcp-status.md`); 3 são maquinaria legada — incluindo `setup-claude.sh`, que curla um `install-server.sh` **que não existe mais**: o cadáver do "a infra sabe se gerir", a topologia que apodreceu em silêncio; 1 é de produto (`zepfinance-setup.md` → repo do ZepFinance); 2 são backlog duplicado. **A triagem está escrita e não executada.**
3. **Perigo armado no working tree do nº 4**: `.claude/settings.json` solto (não rastreado) com `PostToolUse` que roda `claude-sync.sh` após qualquer commit — `git push origin main` **sem condição, com `|| true` engolindo a falha**. Contra guardrail vigente, falha silenciosa por desenho.
4. **O backlog operacional não é bootstrap, e está misturado.** Medido hoje: **11 issues abertas** no nº 4 (o registro de 31/07 dizia 12 com 2 P0 — hoje são **3 P0**: #2 Evolution API desconectada, **#4 zero backup ativo — o PBS foi perdido com o nó do cluster**, #7 cron do Nextcloud parado). Operar infra existente e provisionar infra nova são **naturezas distintas** — a mistura das duas no mesmo repo é parte do que o apodreceu. Onde mora a operação (issues? Demandas § Infra do acervo?) é pergunta deste confronto.
5. **O quinto repo, declarado e sem caso**: o nº 3 mistura provisionar máquina com instalar o harness do `claude-code`. Separar criaria repo que ninguém decidiu — fica como fronteira conhecida até um caso real pedir.

## O que sobreviveu (nada ainda — candidatos a confronto, cada um com custo a medir)

Conduta do confronto: cada alternativa ganha custo próprio antes de qualquer escolha (a forma do ADR-20260801-fase-de-confronto do acervo, praticada enquanto ele tramita).

- **A — o mínimo que prova**: (a1) VM limpa para o par — fecha o veredito aberto e prova o nº 3 de ponta a ponta; (a2) expurgo do nº 4 — executar a triagem que já está escrita (mover doutrina, matar estado morto e maquinaria legada, desarmar o PostToolUse); (a3) decidir a casa do backlog operacional. Sem ferramenta nova; custo estimado: baixo; risco: continua shell puro.
- **B — antecipar o Ansible** (a fase 2 do ADR-ferramentas): provisionamento declarativo para o nº 4. Custo: aprender + portar 25 arquivos; ganha idempotência de graça; contraria o faseamento decidido — exige fato novo para reabrir.
- **C — cloud-init/Terraform**: **já recusado** no ADR-ferramentas; não reabre sem fato novo.

## Por que não os outros

*Vazio — é o que o confronto preenche.*

## Decisão

**Pendente — antessala aberta em 2026-08-01, por ordem do operador.** O apto é leitura dele sobre as quatro perguntas respondidas. Projeto pode dormir aqui o tempo que precisar: dormir na antessala é estado normal de desejo não confrontado.
