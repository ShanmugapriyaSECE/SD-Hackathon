# Jury Q&A prep (every member must know these)
- **Why this service boundary?** Inventory owns stock truth exclusively; payment, order, notification change for different reasons and fail differently.
- **Where exactly is consistency guaranteed?** At the Redis Lua script (fast) and finally at the SQL conditional UPDATE + CHECK constraints (authoritative).
- **Two requests hit inventory at the same time?** Redis serialises script execution; only one decrements the last unit; the other gets SOLD_OUT. Even if both passed, the DB `WHERE available>0` lets only one succeed.
- **Why this concurrency strategy?** Pessimistic locks queue everyone on one row; optimistic causes retry storms; gate + conditional update rejects losers cheaply and stays correct (ADR-1).
- **Why sync here, async there?** User needs immediate reserve/payment answers; order, shipment, notification can be eventual and retried.
- **Payment success then order failure?** Outbox/broker keeps event; idempotent retries; reconciler; refund if unrecoverable.
- **Likely bottleneck?** Hot inventory key and payment gateway; solved by gate, stock buckets, admission control, breaker.
- **What do you sacrifice?** Some latency/fairness and complexity (outbox, saga, two stores) for guaranteed correctness and resilience.
- **How did you validate AI code?** Ran simulation, assertions on invariants, reviewed each line, linked to design assumptions.
