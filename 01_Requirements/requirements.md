# 01 – Requirements & Assumptions

## 1. Problem
Limited-stock flash sale: 10,000 concurrent "Buy Now" requests for 100 units of Product X. No overselling, safe payments, correct order lifecycle, graceful failure recovery.

## 2. Functional requirements
| ID | Requirement |
|---|---|
| FR1 | Browse sale/product pages (cached, read-heavy) |
| FR2 | Cart add/update/remove |
| FR3 | Check stock availability (approximate, cached) |
| FR4 | Reserve inventory atomically with expiry (TTL) |
| FR5 | Checkout against a valid reservation only |
| FR6 | Pay via external gateway; idempotent; handle success/failure/timeout |
| FR7 | Create order after confirmed payment; track lifecycle |
| FR8 | Release reservation on payment failure, timeout, or cancellation |
| FR9 | Fulfilment, shipment, notification, delivery tracking |
| FR10 | Duplicate requests (same idempotency key) return the original result |
| FR11 | Admin: sale configuration, stock load, reports |

## 3. Non-functional requirements
| Area | Target | Type |
|---|---|---|
| Normal load | ~10,000 req/s | Target |
| Flash peak | reason up to 500,000 req/s (edge absorbs most) | Target |
| Latency | Read p95 < 100 ms (cache); reserve p95 < 200 ms; checkout p95 < 500 ms excl. gateway | Target |
| Availability | 99.95% browse; 99.9% purchase path | Target |
| Inventory correctness | successful sales <= stock; never negative | **STRICT GUARANTEE** |
| Idempotency | no duplicate reservation/payment/order per key | **STRICT GUARANTEE** |
| Order integrity | every captured payment ends in an order or a refund | **STRICT (eventual, bounded by reconciliation, e.g. < 15 min)** |
| Durability | RPO = 0 for orders/payments (sync replica), RTO < 5 min | Target |
| Security | HTTPS/TLS1.2+, authN/Z, no card data stored (tokenised gateway reduces PCI scope) | Strict |
| Consistency model | Strong for inventory/payment/order writes; eventual for catalogue, notifications, analytics | Decision |

## 4. Assumptions
1. One hot product (Product X), stock = 100, sale starts at a fixed time.
2. Reservation TTL = 10 minutes normally; 5 minutes during flash sale.
3. Max 1 unit per customer for the sale (limits hoarding).
4. Payment gateway success 95%, failure 5%, occasional timeouts; gateway supports idempotency keys.
5. Customers are authenticated before Buy Now (login done before sale starts).
6. 2% of requests are duplicates (double-click/retry).
7. Order Service may be down ~30 s; messaging layer is durable.
8. Cloud deployment, 3 availability zones, Kubernetes with autoscaling.

## 5. Constraints
- Third-party gateway rate limits and latency are outside our control.
- Hot-row contention on a single inventory record.
- Team of 3, one day: design-first, small prototype only.

## 6. Critical dependencies
Payment gateway, Redis cluster, primary SQL DB, message broker, CDN/WAF, shipping partner API, notification provider.

## 7. Strict guarantees vs targets
- **Strict:** no oversell, no duplicate charge/order, no lost paid order, reservations eventually released.
- **Targets:** latency, throughput, availability numbers, notification timing.

## 8. Back-of-envelope
- 500,000 req/s peak; assume 90%+ served by CDN/cache/waiting room -> <= 50,000 req/s reach the API gateway.
- Only buy attempts (<= ~10,000 in the first seconds) reach the Inventory gate; one Redis shard handles 100k+ ops/s, so the gate is not the limit.
- Only ~100 (+ retries after releases) ever reach payment -> payment path load is small by design.
