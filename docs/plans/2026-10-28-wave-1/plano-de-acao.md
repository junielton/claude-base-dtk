# Plano de ação — dtk como o melhor toolkit pra você

Critério: qualidade pra uso próprio. Estrelas e adoção estão fora.

## 1. O review do dtk é o melhor possível?

**No processo, sim. No conteúdo que ele pega, não ainda.**

O que ninguém no ecossistema Claude Code tem e o dtk tem: memória carregada depois da análise, verificador adversarial por finding com ônus da prova por severidade, `tone-lint` + voz do autor + gate antes de postar, e uma métrica real (`outcomes.py`). Isso é o **processo** de review mais maduro que a pesquisa encontrou fora do tier pago.

Onde o tier premium (Anthropic managed/ultra, CodeRabbit, pr-review-toolkit) pega coisas que o nosso não pega:

| Lacuna | Quem faz | O que o dtk faz hoje | Efeito |
|---|---|---|---|
| **Finders especializados em paralelo**: um agente só pra silent failures, outro pra testes, outro pra type/contract design, outro pra error handling, outro pra comentários | `pr-review-toolkit` (Anthropic), managed Code Review ("multiple agents search in parallel, then verified") | 1 agente generalista, 4 passes sequenciais, checklist com sabor Eloquent | Recall menor em classes de bug que exigem lente estreita |
| **Contexto estreito por finding** | SWE-PRBench: prompt estruturado de ~2k tokens bate full-context; "attention dilution" | Review lê a diff inteira numa sessão só | Mais contexto = pior detecção |
| **Gate empírico no verificador** | ultra ("independently reproduced"), CodeRabbit Runtime Analysis, Refute-or-Promote (10 revisores unânimes errados, 1 teste matou) | Verificador só relê e grepa; "Never run tests" | Falso positivo plausível sobrevive |
| **Assimetria de contexto no verificador** | Refute-or-Promote ("context asymmetry", cold-start reviewers) | Verificador recebe `reasoning` do revisor → anchoring | Verificador tende a concordar |
| **Crítico cross-model** | Refute-or-Promote | `model: inherit` | Pontos cegos correlacionados |
| **Citação obrigatória `file:line` pra claims de comportamento** | REVIEW.md idiom da Anthropic | Não é regra dura | Claims por inferência de nome passam |
| **Lições que outros revisores consomem** | Copilot, CodeRabbit, Greptile leem `CLAUDE.md`/`REVIEW.md`/`copilot-instructions.md` | `docs/lessons/` só o dtk lê | Copilot do teu time não aprende com as tuas lições |
| **Ciclo de vida de regra**: candidata → ativa → aposentada por taxa de aceite | CodeRabbit pending learnings, Cursor learned rules, Graphite per-rule acceptance | Lição vira ativa na hora, nunca aposenta | Lições ruins acumulam |

Conclusão: **importar 1, 3, 4, 6 e 7 fecha a lacuna de conteúdo mantendo o processo que já é superior.**

## 2. O que trazer do mercado pra dentro do dtk (e onde liga)

| # | Importar | De onde | Liga em |
|---|---|---|---|
| I1 | Finders especializados paralelos (silent-failure, tests, type-design, error-handling, comments) com contexto estreito, depois merge + dedup + verificador | pr-review-toolkit, SWE-PRBench | review, review-local, review-peer |
| I2 | Verificador v2: assimetria (veredito antes de ler `reasoning`), gate empírico opcional em `blocking` (rodar o teste/REPL que falsifica), modelo diferente do revisor | Refute-or-Promote, ultra | `dtk-review-verifier` + evals |
| I3 | Regra dura: claim de comportamento exige `file:line` da fonte | REVIEW.md da Anthropic | review-core + verificador |
| I4 | Exportar lições pra `REVIEW.md` e `.github/copilot-instructions.md` (seção gerada) | Copilot/CodeRabbit/Greptile | learn-from-review |
| I5 | Ciclo de vida de lição: `candidate` → `active` → `retired`, dirigido por `outcomes.py` | CodeRabbit, Cursor, Graphite | learn-from-review + review-outcomes |
| I6 | `dtk:review-outcomes` como skill com métrica definida (posted / refuted / accepted / resolved-by-merge / marked-wrong) | ninguém publica neutro | novo, sobre `outcomes.py` |
| I7 | Override do `code-review` bundled: skill de projeto chamada `code-review` que roteia pro pipeline dtk (docs da Anthropic convidam isso) | docs `/code-review` | novo, fino |
| I8 | Recibos de verificação no report-back: comando, exit code, "rodou após a última edição" | superpowers verification-before-completion, arXiv 2605.29442 | report-back + ship |
| I9 | Eval de alinhamento no dsqa/mockup-qa (crop, escala, viewport) com fixtures; parar de instalar puppeteer no projeto do usuário | Applitools "deterministic check in the loop" | dsqa, mockup-qa |
| I10 | `claude plugin validate --strict` + testes existentes + trigger-evals no CI | docs plugin-evals, `/skill-doctor` | `.github/workflows` |
| I11 | Interop com `gh stack` / git-town quando houver metadata | GitHub Stacked PRs (jul/2026) | git-rebase-onto |
| I12 | Mockup aprovado → `html_to_figma` (opcional) | Figma Config India 2026 | create-mockup |

## 3. Timeline

### Onda 1 — eu despacho agora (worktrees independentes, paralelas)

| WT | Escopo | Toca | Esforço |
|---|---|---|---|
| **W1 higiene** | LICENSE MIT; README (HTTPS, incluir `draft-to-prompt` e `laravel-scaffold-design-panel`); Releases + CHANGELOG no `auto-version.yml`; remover refs mortas (`dtk:update-design`, `speak-notify`, "Phase 7" do implement-design) | README, workflow, 3 SKILL.md | P |
| **W2 scripts** | Mover `bin/skill-scripts/` → `scripts/` (raiz `bin/` bloqueia claude.ai/Cowork); um resolver só (`${CLAUDE_PLUGIN_ROOT}`); corrigir caminho relativo cru de `debug-gh-action` e `$MK` hard-coded do trio de mockup; testes continuam passando | 12 skills + bin | M |
| **W3 verifier v2** | I2 + I3: duas fases (veredito cego → só então `reasoning`), gate empírico opt-in em `blocking` com allowlist de comandos, `model` configurável; evals 9/9 mantidos + casos novos (anchoring, empírico) | `agents/dtk-review-verifier.md`, evals | M |
| **W4 lições** | I4 + I5: export gerado pra `REVIEW.md`/`copilot-instructions.md`; frontmatter `status: candidate/active/retired`; `outcomes.py` alimenta aposentadoria | learn-from-review, outcomes.py | M |
| **W5 review-outcomes** | I6: skill pública sobre `outcomes.py`, definições explícitas, saída tabular | novo SKILL.md | P |
| **W6 review-core** | Extrair o workflow repetido 4× pra `skills/review-core/references/`; checklist stack-neutra; alinhar vocabulário de saída com o rail do report-back (hoje review usa emoji, report-back proíbe) | review, review-local, review-peer, review-publish | M |
| **W7 dsqa deps** | I9: puppeteer/pixelmatch em cache do plugin, não nas devDependencies do projeto; fixture mínima de alinhamento | dsqa, mockup-qa | P/M |
| **W8 CI** | I10: rodar os 36 testes offline + 19 node + `plugin validate --strict` em PR | `.github/workflows` | P |

### Onda 2 — depois que W6 mergear (dependem do review-core)

| WT | Escopo | Esforço |
|---|---|---|
| **W9 finders** | I1: 4–5 subagentes especializados com contexto estreito, merge + dedup, tudo passa pelo verificador | G |
| **W10 descrições** | 11 descrições curtas → trigger-rich com exclusões; suíte de trigger-eval com `claude plugin eval` | M |
| **W11 override** | I7: skill `code-review` que roteia pro dtk | P |
| **W12 report-back recibos** | I8 no report-back e no ship | P |

### Onda 3 — opcional, depois

I11 (gh stack interop), I12 (html_to_figma), separar `laravel-scaffold-design-panel` em plugin próprio.

## 4. O que fica contigo

| Decisão / ação | Por quê é tua | Minha recomendação |
|---|---|---|
| Verificador pode **executar** testes/REPL (gate empírico)? | Política de permissão e custo | Sim, opt-in, allowlist (`php artisan test --filter`, `node -e`, `grep`) |
| Lição vira ativa direto ou passa por PR? | Fluxo do time | Direto pra ti; `candidate` quando vier de review-peer |
| Manter gatilhos pt-BR nas descrições? | É teu uso | Manter; custo é só caracteres de descrição |
| Anonimizar `transwest`/`dberri`/`BTP-*` em docs e fixtures? | Só importa se publicar | Fazer só se for submeter ao marketplace |
| Graduar `address-review`, `land-prs`, `scope-task`, `new-task`, `dispatch-pr-review`, `juni-vox` de `~/.claude/skills` pro dtk? | Mudança de "onde mora" | Sim pras 4 primeiras com Harnu opcional; `juni-vox` fica pessoal |
| Submeter ao `claude-plugins-community` / skills.sh | Tua conta | Só se quiser scan + analytics de graça |
| Rodar `/skill-doctor` numa sessão tua | Mede custo de contexto da tua instalação real | Antes e depois da W10 |
| Testar `ship` ponta a ponta num PR real após W2 | Mudança de caminho de scripts é a mais arriscada | Primeiro PR depois do merge da W2 |

## 5. Como despacho

`harnu:orchestrate-delivery`: 1 card por WT, 1 worktree + 1 sessão por card, PR por unidade, verificação independente dos ACs, Delivery Report no fim. Onda 1 = 8 sessões; respeita o teto de WIP do Harnu (default 5), então as 3 últimas entram quando vagar.
