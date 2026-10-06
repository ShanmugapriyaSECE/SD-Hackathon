# 12 – Practical Test Case Walkthroughs
Stock=100, users=10,000, pay success 95%, duplicates 2%, Order Service down 30 s.

1. **Successful purchase:** POST /reservations (key K1) -> gate OK -> DB reserve -> 201 -> POST /checkout (key P1) -> gateway CAPTURED -> payment+reservation CONFIRMED+outbox -> OrderConfirmed -> reservation SOLD.
2. **Failed payment:** gateway FAILED -> payment FAILED, reservation RELEASED, `available+1`, gate +1, customer notified; unit can be won by another user.
3. **Duplicate Buy:** same Idempotency-Key -> gate/DB unique key detects -> returns same reservation (200); no second unit consumed.
4. **Payment success then Order Service down:** PaymentCaptured stays in outbox/broker; retries with backoff; after 30 s Order Service creates order (UNIQUE payment_id avoids duplicates); user sees "processing" meanwhile; reconciler is a backstop.
5. **Inventory reaches zero:** gate returns SOLD_OUT immediately (409), no DB access; UI flips to "Sold out / notify me"; cache updated.
6. **50x traffic:** see 08_Scalability_Reliability section 5.
7. **DB failure:** promote sync replica; retries with same keys; constraints prevent oversell. **Gateway failure:** breaker opens, "try later", reservation TTL extended once, resume after half-open success.
