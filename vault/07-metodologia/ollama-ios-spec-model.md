---
tags: [metodologia, ollama, ios-spec, llm, tooling]
aliases: [ollama ios-spec, byescaleira/ios-spec, glm-5.2 ollama]
related: [[nebula-clean-architecture-toolkit]]
---

# Ollama `byescaleira/ios-spec` — modelo especialista iOS (Cosmos/Nebula)

Investigação da doc do Ollama para publicar um modelo especialista iOS baseado em **GLM 5.2**, com a restrição de **não caber na máquina local** (pesos full ~467 GB; Q2 ~241 GB).

## Como o Ollama funciona (ground truth da doc)

- Modelos = layers content-addressed (estilo OCI/Docker). Modelo derivado (`FROM <base>`) **compartilha** as layers de peso da base; só cria layers finas de metadata (SYSTEM, PARAMETER, TEMPLATE).
- **`ollama create` (CLI) exige a base presente localmente** — a doc do Modelfile diz textualmente: "The base model must be present on the host before `ollama create` runs — pull it first with `ollama pull`." Ou seja, o caminho CLI padrão **não** evita baixar a base.
- **`ollama push` lê blobs do armazenamento local** e faz upload. Layers que já existem em `registry.ollama.ai` são deduplicadas (HEAD `/api/blobs/:digest` → 200 pula upload), então push de um derivado fino envia só as layers novas — mas elas precisam existir localmente.
- **`/api/create` + `/api/blobs`** permitem criar remotamente num servidor que já tem os pesos (POST do GGUF como blob por digest, depois create referenciando o digest). Útil só se você tem um servidor grande; o registry público continua exigindo blobs locais no cliente que faz push.

## GLM 5.2 na biblioteca Ollama

- Tag oficial **`glm-5.2:cloud`** — roteia inferência para a Z.ai (hospedado), **sem baixar pesos**. Só cacheia config local. Adicionado ~jun/2026 (PR #16724).
- Variante GGUF local **`frob/glm-5.2`** (~467 GB, 1M contexto, exige Ollama v0.30+).
- Rodar local full: Q2 ~241 GB disco + 256 GB RAM; Q4_K_M ~476 GB; FP16 ~1.7 TB. Impraticável num Mac comum.

## Resposta direta: "dá pra publicar sem baixar?"

**Não pelo caminho CLI padrão para um derivado de GLM 5.2 full.** `ollama create` precisa da base local; `ollama push` precisa dos blobs locais. E mesmo depois de publicado, **rodar** `byescaleira/ios-spec` local ainda exigiria os 467 GB da base — publicar não resolve o "não cabe".

## Caminhos viáveis (em ordem de pragmatismo)

1. **Usar `glm-5.2:cloud` + system prompt, sem publicar derivado.** É a forma real de ter "GLM 5.2 especialista iOS" sem baixar nada. Passar as guidelines Cosmos/Nebula como SYSTEM em runtime (campo `system` da API OpenAI-compat em `http://localhost:11434/v1`, ou colar no `ollama run`). Zero disco.
2. **Compartilhar o Modelfile via VCS (recomendado pela doc, "Option 1").** Commitar `Modelfile.ios-spec` no repo com `FROM glm-5.2:cloud` + SYSTEM (todas as guidelines) + PARAMETER. Cada runner faz `ollama create ios-spec -f Modelfile.ios-spec` e `ollama run ios-spec`. Sem push, sem 467 GB. **Atenção:** `FROM glm-5.2:cloud` num Modelfile não está confirmado pela doc — cloud tags não têm blobs locais; se `create` rejeitar, cair no caminho 1 (system prompt em runtime).
3. **Publicar `byescaleira/ios-spec` sobre base local de coding (recomendado: `qwen3-coder:30b`).** Base pequena demais (`llama3.2` 3B) = inteligência fraca; o ponto ótimo é um modelo de coding que **cabe** num Mac dev mas tem capacidade real. **Top pick jul/2026: `qwen3-coder:30b`** (Qwen3-Coder 30B-A3B, MoE — só 3.3B ativos/token → rápido em Apple Silicon; 262K contexto; Apache 2.0; tag oficial na biblioteca). Q4_K_M ~18 GB disco, ~25–32 GB RAM ideal. Tiers por RAM do Mac: 32GB+ → `qwen3-coder:30b` (Q4, sweet spot); 24GB → mesmo modelo com contexto reduzido; 16GB → `qwen2.5-coder:7b` (~5 GB) ou `qwen3-coder:30b` em Q2 (perda de qualidade); 64GB+ → `llama3.3:70b` (GPT-4-class, ~40 GB Q4) se qualidade bruta > velocidade. Sampling recomendado p/ Qwen3-Coder: temp 0.7, top_p 0.8, top_k 20, repetition_penalty 1.05; modo non-thinking. Vantagem sobre GLM 5.2: a base **cabe** no Mac, então `ollama pull byescaleira/ios-spec` + rodar funciona em qualquer máquina dev — história publicável coerente.
4. **Buildar numa VM/servidor com ≥500 GB.** `create` + `push` lá; push sobe só delta. Mas quem fizer `pull` só consegue **rodar** numa máquina com os 467 GB da base — não ajuda no Mac.

## Recomendação

Para o objetivo declarado ("GLM 5.2 especialista iOS seguindo Cosmos/Nebula, sem caber local"): **caminho 1 + 2 combinados** — usar `glm-5.2:cloud` como motor (sem pesos locais) e versionar o `Modelfile.ios-spec` no repo como fonte do system prompt especialista. **Não** perseguir `ollama push byescaleira/ios-spec` sobre GLM 5.2 — publicar não contorna o fato de que rodar exige 467 GB. Se quiser mesmo uma coisa publicável com `ollama pull`, aceite o tradeoff do caminho 3 (base pequena).

## Fontes

- Modelfile ref: https://github.com/ollama/ollama/blob/main/docs/modelfile.mdx
- API create/push/blobs: https://github.com/ollama/ollama/blob/main/docs/api.md
- GLM 5.2 cloud no launch registry: https://github.com/ollama/ollama/issues/16708
- GLM 5.2 cloud setup: https://avenchat.com/blog/run-glm-5.2-in-ollama
- GGUF local: https://ollama.com/frob/glm-5.2