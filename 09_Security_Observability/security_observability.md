# 09 – Security & Observability

## Security
| Area | Design |
|---|---|
| AuthN/AuthZ | OAuth2/OIDC login; short-lived JWT; scope/role checks; users can only access their own cart/order/reservation |
| Transport | HTTPS/TLS 1.2+ everywhere, mTLS between services, HSTS |
| Rate limiting / abuse | WAF bot rules, CAPTCHA at queue entry, per-IP and per-user token buckets, 1 unit per customer, device fingerprint signals |
| Input validation | DTO schema validation, parameterised queries, size limits |
| Payment data | Client-side tokenisation by gateway; we store only token/last4 + tx_ref (PCI scope minimised); no card data in logs |
| Secrets | Vault/KMS, rotation, no secrets in code/env files |
| Audit | Immutable `state_audit` + admin action logs, who/when/what |
| Data protection | Encryption at rest, PII masking in logs, least-privilege DB users |

## Observability
### Key metrics (RED + business)
| Metric | Alert example |
|---|---|
| Request rate, p50/p95/p99 latency, error rate per service | p95 > 500 ms for 5 min |
| `inventory_reservation_success/failure_total`, sold-out rate | – |
| **Inventory invariant**: `available+reserved+sold == total` and `sold <= total` | ANY violation -> page immediately |
| Redis gate count vs DB available (drift) | drift != 0 for > 1 min |
| Payment success/failure/unknown rate, gateway latency, breaker state | failure > 10%, breaker OPEN |
| Payments CAPTURED without order > 2 min | > 0 -> alert |
| Queue lag / DLQ depth | lag > threshold, DLQ > 0 |
| Order conversion (reserved -> paid -> confirmed) | drop > 20% vs baseline |
| Reservation expiry backlog | expired-not-released > 0 |

### Structured logs (JSON)
`{ts, level, service, trace_id, event: "RESERVATION_CREATED", reservation_id, customer_id(hashed), product_id, idempotency_key, result, latency_ms}` for events: RESERVATION_CREATED/REJECTED/EXPIRED, PAYMENT_CAPTURED/FAILED/UNKNOWN, ORDER_CREATED, REFUND_ISSUED, CIRCUIT_OPENED.

### Distributed tracing
OpenTelemetry; trace id generated at the gateway and propagated through HTTP headers and broker message headers across checkout -> payment -> order -> shipment. Dashboards (Grafana) per sale: funnel, stock gauge, payment health, queue lag.
