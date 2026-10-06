# 12 – Final 5-Minute Pitch (script outline)

| Time | Slide | Say |
|---|---|---|
| 0:00-0:30 | 1 Problem | Flash sale, 10,000 buyers, 100 units. One oversold unit = refund + brand damage. |
| 0:30-1:00 | 2 Requirements | Strict: no oversell, no duplicate charge, no lost paid order. Targets: 500k req/s peak, p95 < 200 ms. |
| 1:00-2:00 | 3 HLD | CDN/WAF -> waiting room -> gateway -> services; Redis gate; SQL truth; broker; workers. Why each exists. |
| 2:00-3:00 | 4 Critical design | Redis Lua = single atomic decision point; 100 win, 9,900 get SOLD_OUT instantly; DB conditional update + constraints = safety net; TTL expiry. |
| 3:00-3:45 | 5 Payment & order | Idempotency key + tx_ref; breaker + timeout; UNKNOWN -> reconcile; outbox so Order outage of 30 s loses nothing. |
| 3:45-4:30 | 6 LLD/SOLID/Patterns | Class diagram of Payment: `PaymentGateway` interface, Adapter, Factory, Circuit Breaker decorator; OCP/DIP example. |
| 4:30-5:00 | 7 Scale & validation | 50x: edge absorbs, shard stock buckets; simulation: sold=98<=100, orders=captured payments. |

## Final jury question – answer flow
1. 10,000 requests hit CDN/WAF; bots dropped; waiting room admits at a controlled rate.
2. Gateway authenticates, rate limits, checks Idempotency-Key.
3. Inventory service runs the Redis Lua script: first 100 get a reservation (TTL), the rest SOLD_OUT.
4. Winners' reservations are persisted via conditional SQL update + outbox in one transaction.
5. Winners checkout; payment with unique tx_ref through circuit breaker.
6. 95% captured -> event -> Order Service creates order idempotently (retries if down) -> reservation SOLD.
7. 5% failed/abandoned -> reservation released -> unit returned -> later users may win it.
8. Reconciler fixes UNKNOWN payments and paid-without-order cases. Final state: sold <= 100, every paid customer has exactly one order.
