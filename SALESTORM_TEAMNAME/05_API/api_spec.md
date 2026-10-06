# 05 – API & Event Design

Base: `https://api.salestorm.example/v1`  | Auth: `Authorization: Bearer <JWT>` | All write calls require `Idempotency-Key` header (UUID).
Errors use `{ "error": {"code": "...", "message": "...", "trace_id": "..."} }`.

| # | Method & Endpoint | Request | Success | Errors |
|---|---|---|---|---|
| 1 | GET `/products/{id}` | – | 200 product (cached) | 404 |
| 2 | GET `/sales/{id}/availability` | – | 200 `{approx_available}` (cache, approximate) | 404 |
| 3 | POST `/cart/items` | `{product_id, qty}` | 201 cart | 400, 401 |
| 4 | POST `/reservations` | `{product_id, qty:1}` + Idempotency-Key | 201 `{reservation_id, expires_at}`; duplicate -> 200 same body | 409 `SOLD_OUT`, 409 `ALREADY_RESERVED`, 429 `RATE_LIMITED`, 503 `QUEUE_FULL` (+Retry-After) |
| 5 | GET `/reservations/{id}` | – | 200 `{status, expires_at}` | 404 |
| 6 | DELETE `/reservations/{id}` | – | 204 (release) | 404, 409 invalid state |
| 7 | POST `/checkout` | `{reservation_id, payment_method, token}` + Idempotency-Key | 200 `{payment_status, order_id?}`; 202 `PROCESSING` if gateway timeout | 402 `PAYMENT_FAILED`, 410 `RESERVATION_EXPIRED`, 409 |
| 8 | GET `/payments/{id}` | – | 200 status | 404 |
| 9 | GET `/orders/{id}` | – | 200 order + state | 404, 403 |
| 10 | POST `/orders/{id}/cancel` | – | 200 CANCELLED (+refund) | 409 not cancellable |
| 11 | GET `/orders/{id}/tracking` | – | 200 shipment status | 404 |

### Status & error handling rules
- 4xx = client/business problem (do not retry blindly); 5xx/503 = retry with backoff + same Idempotency-Key.
- Same key + same body = same response; same key + different body = 422.
- Rate limit per user and per IP at the gateway; token bucket.

## Commands vs events
| Type | Name | Owner (producer) | Consumers |
|---|---|---|---|
| Command | ReserveInventory | Checkout/Gateway -> Inventory | Inventory |
| Command | ChargePayment | Checkout -> Payment | Payment |
| Event | ReservationCreated | Inventory | Analytics |
| Event | ReservationExpired / ReservationReleased | Inventory (expiry worker) | Cart, Notification |
| Event | PaymentCaptured | Payment | Order, Inventory (confirm), Notification |
| Event | PaymentFailed | Payment | Inventory (release), Notification |
| Event | OrderConfirmed | Order | Shipment, Notification, Analytics |
| Event | OrderShipped / OutForDelivery / Delivered | Shipment | Order, Notification |
| Event | RefundRequested | Reconciler/Order | Payment |

**Rules:** one owner per event; consumers are idempotent (`processed_event` table); events carry `event_id`, `aggregate_id`, `occurred_at`, `version`; partition key = reservation/order id for ordering; poison messages -> DLQ.
