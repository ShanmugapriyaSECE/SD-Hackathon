# 11 – AI-Assisted Validation (Optional)

Run: `python3 simulation.py` (Python 3.8+, no dependencies). Output saved in `simulation_results.txt`.

## What it validates (links to design)
| Design assumption | Simulation evidence |
|---|---|
| Atomic gate + conditional DB update prevents oversell | `sold <= 100`, invariant `available+reserved+sold = total` asserted |
| Idempotency keys | Duplicate requests from winners return the existing reservation (counted "Duplicates idempotent"); duplicates from losers are simply rejected again |
| Payment failure releases reservation | 5% failures -> `RELEASED`, unit returned |
| Expiry worker | Abandoned reservations released |
| Outbox + retry during Order Service outage | Orders = 0 during outage, then exactly = captured payments after recovery |

## Reading the result
Reservations won (~106) > 100 is expected: failed payments/abandonments release units that later arrivals can win. **Sold never exceeds 100.** Final `available` > 0 means released units stayed unsold because all users had already been rejected; in production, waiting-room retries or "notify me" can reuse them.

## Limitations (be honest in the defense)
Threads + locks emulate Redis/SQL atomicity; they do not measure real latency/throughput. Next step: Locust/JMeter against a small API stub with real Redis + PostgreSQL.

## AI Usage Note (edit before submission)
- **Tool:** Claude (Anthropic) - used to draft the beta documents, Mermaid diagrams, SQL DDL, and simulation script.
- **Purpose:** accelerate documentation and the validation script, after the architecture direction (Redis gate + SQL conditional update + outbox/saga) was chosen.
- **Prompt summary:** "Design-first flash-sale hackathon brief -> create full project folder with HLD, LLD, DB, API, patterns, ADR, simulation."
- **Validation:** simulation run and assertions checked; team must review every diagram/claim, change numbers to team assumptions, and be able to explain each file.
- **Not delegated to AI (team must own):** final architecture choices, trade-off defense, jury answers.
