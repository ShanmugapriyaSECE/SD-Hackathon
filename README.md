# SALESTORM – Flash-Sale System Design (BETA v0.1)
SYSCRAFTERS 2026 | Design-First, AI-Assisted System Design Hackathon

**Team:** TEAMNAME  |  **Members:** (add names + roles)  |  **Date:** 5 Oct 2026

## One-line solution
Protect the 100 units with ONE atomic decision point (Redis Lua gate, backed by a conditional SQL update as source of truth),
shed excess load early (CDN/WAF, rate limit, waiting room), and keep payment/order eventually consistent using
idempotency keys + transactional outbox + saga/reconciliation.

## Folder map (matches brief, Section 15)
| Folder | Contents |
|---|---|
| 01_Requirements | Requirements & assumptions |
| 02_HLD | Context, container, component, deployment diagrams (Mermaid) |
| 03_LLD | Class, 3 sequence diagrams, state diagrams |
| 04_Database | ER diagram + `schema.sql` |
| 05_API | API spec, events, `openapi.yaml` |
| 06_SOLID | SOLID mapping |
| 07_Design_Patterns | Pattern mapping |
| 08_Scalability_Reliability | Scaling, 50x, failure handling |
| 09_Security_Observability | Security, metrics, logs, tracing, alerts |
| 10_ADR | Architecture Decision Records |
| 11_AI_Assisted_Validation | `simulation.py`, results, AI-use note |
| 12_Presentation | 5-min pitch script, jury Q&A, walkthroughs |

## How to view diagrams
Diagrams are Mermaid. Paste into https://mermaid.live, or view on GitHub/GitLab (renders natively), or VS Code with a Mermaid plugin.

## TODO for next version (beta -> final)
See `TODO_UPGRADE.md`.
