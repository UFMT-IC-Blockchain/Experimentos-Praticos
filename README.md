# Experimentos Práticos — Stellar Testnet + Horizon

[🇧🇷 Português](README.md) | [🇬🇧 English](README.en.md)

Repositório de experimentos práticos do mestrado com a **Stellar Testnet** e o **Horizon** (API), rodando em **Docker**. Contém diários de bordo, relatórios de monitoramento de ledgers/mempool, análises de sincronização, otimização de armazenamento e setups Docker (Core + Horizon, MainNet, Core-only).

## Estrutura

```
pt/    → Documentação em português (BR)
en/    → Documentação traduzida para inglês (US)
```

- **`pt/Experimentos-Dezembro-2025/`** — Diários de bordo (Dia 1, 2, 4, 5)
- **`pt/Experimentos-Julho-2026/`** — Relatórios e análises de experimentos de 15 a 26/07/2026
  - `2026-07-15` — Sincronização inicial do nó Stellar
  - `2026-07-16` — Monitoramento de 30/100/500 ledgers, mempool e transações
  - `2026-07-17` / `2026-07-20` — Sincronização e catch-up de nós
  - `2026-07-21` — Plano de implementação: split Core + Horizon, análise SQL
  - `2026-07-26` — Otimização de armazenamento do validador
  - `Docker-Core-Horizon-Separado` / `Docker-MainNet` / `Docker-MainNet-CoreOnly` — Setups Docker
- **`LICENSE`** — Licença do projeto

## Idiomas

| Idioma | Documentação |
|--------|--------------|
| Português (BR) | [`pt/`](pt/) |
| English (US) | [`en/`](en/) |
