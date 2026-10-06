-- SALESTORM beta schema (PostgreSQL style)
CREATE TABLE customer (
  customer_id BIGSERIAL PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  name VARCHAR(120) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE category (
  category_id SERIAL PRIMARY KEY,
  name VARCHAR(100) UNIQUE NOT NULL
);
CREATE TABLE product (
  product_id BIGSERIAL PRIMARY KEY,
  category_id INT REFERENCES category(category_id),
  name VARCHAR(200) NOT NULL,
  price NUMERIC(12,2) NOT NULL CHECK (price >= 0),
  active BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE TABLE inventory (
  inventory_id BIGSERIAL PRIMARY KEY,
  product_id BIGINT UNIQUE NOT NULL REFERENCES product(product_id),
  available_quantity INT NOT NULL CHECK (available_quantity >= 0),
  reserved_quantity  INT NOT NULL CHECK (reserved_quantity  >= 0),
  sold_quantity      INT NOT NULL CHECK (sold_quantity      >= 0),
  total_quantity     INT NOT NULL,
  version BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT inv_balance CHECK (available_quantity + reserved_quantity + sold_quantity = total_quantity)
);
CREATE TABLE sale (
  sale_id BIGSERIAL PRIMARY KEY,
  name VARCHAR(150) NOT NULL,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  max_per_customer INT NOT NULL DEFAULT 1
);
CREATE TABLE sale_product (
  sale_id BIGINT REFERENCES sale(sale_id),
  product_id BIGINT REFERENCES product(product_id),
  sale_price NUMERIC(12,2) NOT NULL,
  PRIMARY KEY (sale_id, product_id)
);
CREATE TABLE coupon (
  coupon_id BIGSERIAL PRIMARY KEY,
  code VARCHAR(40) UNIQUE NOT NULL,
  discount_pct INT CHECK (discount_pct BETWEEN 0 AND 100),
  valid_until TIMESTAMPTZ
);
CREATE TABLE cart (
  cart_id BIGSERIAL PRIMARY KEY,
  customer_id BIGINT NOT NULL REFERENCES customer(customer_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE cart_item (
  cart_id BIGINT REFERENCES cart(cart_id),
  product_id BIGINT REFERENCES product(product_id),
  quantity INT NOT NULL CHECK (quantity > 0),
  PRIMARY KEY (cart_id, product_id)
);
CREATE TABLE inventory_reservation (
  reservation_id UUID PRIMARY KEY,
  inventory_id BIGINT NOT NULL REFERENCES inventory(inventory_id),
  customer_id BIGINT NOT NULL REFERENCES customer(customer_id),
  quantity INT NOT NULL DEFAULT 1,
  status VARCHAR(20) NOT NULL CHECK (status IN
     ('RESERVED','PAYMENT_PENDING','CONFIRMED','SOLD','RELEASED','EXPIRED')),
  idempotency_key VARCHAR(80) NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_resv_expiry ON inventory_reservation(status, expires_at);
-- one active reservation per customer per product (1 unit per customer rule)
CREATE UNIQUE INDEX uq_resv_active_per_customer
  ON inventory_reservation(customer_id, inventory_id)
  WHERE status IN ('RESERVED','PAYMENT_PENDING','CONFIRMED','SOLD');

CREATE TABLE payment (
  payment_id UUID PRIMARY KEY,
  reservation_id UUID NOT NULL REFERENCES inventory_reservation(reservation_id),
  tx_ref VARCHAR(80) NOT NULL UNIQUE,         -- unique transaction reference sent to gateway
  idempotency_key VARCHAR(80) NOT NULL UNIQUE,
  amount NUMERIC(12,2) NOT NULL,
  status VARCHAR(20) NOT NULL CHECK (status IN
     ('PENDING','CAPTURED','FAILED','UNKNOWN','REFUNDED')),
  gateway_ref VARCHAR(100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_payment_recon ON payment(status, updated_at);

CREATE TABLE "order" (
  order_id UUID PRIMARY KEY,
  customer_id BIGINT NOT NULL REFERENCES customer(customer_id),
  payment_id UUID NOT NULL UNIQUE REFERENCES payment(payment_id), -- 1 order per payment
  status VARCHAR(20) NOT NULL CHECK (status IN
     ('CREATED','PAYMENT_PENDING','CONFIRMED','PROCESSING','SHIPPED',
      'OUT_FOR_DELIVERY','DELIVERED','CANCELLED')),
  total_amount NUMERIC(12,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_order_customer ON "order"(customer_id, created_at DESC);
CREATE TABLE order_item (
  order_id UUID REFERENCES "order"(order_id),
  product_id BIGINT REFERENCES product(product_id),
  quantity INT NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(12,2) NOT NULL,
  PRIMARY KEY (order_id, product_id)
);
CREATE TABLE shipment (
  shipment_id UUID PRIMARY KEY,
  order_id UUID UNIQUE NOT NULL REFERENCES "order"(order_id),
  carrier VARCHAR(60), tracking_no VARCHAR(80),
  status VARCHAR(30) NOT NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE notification (
  notification_id UUID PRIMARY KEY,
  order_id UUID REFERENCES "order"(order_id),
  channel VARCHAR(10) NOT NULL, status VARCHAR(10) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Reliability tables
CREATE TABLE outbox_event (
  event_id UUID PRIMARY KEY,
  aggregate_type VARCHAR(30) NOT NULL, aggregate_id VARCHAR(60) NOT NULL,
  event_type VARCHAR(50) NOT NULL, payload JSONB NOT NULL,
  published BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_outbox_unpublished ON outbox_event(published, created_at);
CREATE TABLE processed_event (               -- idempotent consumers
  consumer VARCHAR(50), event_id UUID, processed_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (consumer, event_id)
);
CREATE TABLE state_audit (                   -- audit trail
  audit_id BIGSERIAL PRIMARY KEY,
  entity VARCHAR(30), entity_id VARCHAR(60),
  from_state VARCHAR(30), to_state VARCHAR(30),
  actor VARCHAR(60), at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- THE core oversell-proof statement (executed inside the reserve transaction):
-- UPDATE inventory
--    SET available_quantity = available_quantity - 1,
--        reserved_quantity  = reserved_quantity + 1,
--        version = version + 1, updated_at = now()
--  WHERE product_id = :pid AND available_quantity > 0;   -- 0 rows affected => SOLD_OUT
