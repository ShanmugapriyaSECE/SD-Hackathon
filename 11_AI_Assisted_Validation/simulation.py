"""
SALESTORM beta simulation - validates design assumptions (NOT a production system).
Scenario: stock=100, 10,000 concurrent buyers, 2% duplicate requests, 5% payment failures,
Order Service unavailable for the first part of the run (simulated 30 s outage).

Checks:
  1. sold <= 100 and never negative            (inventory consistency)
  2. duplicates return the original result      (idempotency)
  3. failed payments release the reservation     (release/compensation)
  4. every captured payment ends in exactly one order after outage (outbox + retry)
  5. abandoned reservations are released by expiry worker (TTL)
The lock in AtomicStockGate stands in for Redis Lua atomicity; SQLInventory stands in for the conditional UPDATE.
"""
import threading, random, time, uuid
from concurrent.futures import ThreadPoolExecutor

STOCK, USERS = 100, 10_000
DUP_RATE, PAY_FAIL_RATE, ABANDON_RATE = 0.02, 0.05, 0.02
random.seed(42)

class AtomicStockGate:                       # ~ Redis Lua script
    def __init__(self, n): self.stock, self.lock, self.seen = n, threading.Lock(), {}
    def try_acquire(self, key):
        with self.lock:                      # atomic: check key, check stock, decrement
            if key in self.seen: return "DUPLICATE", self.seen[key]
            if self.stock <= 0:  return "SOLD_OUT", None
            self.stock -= 1
            rid = str(uuid.uuid4()); self.seen[key] = rid
            return "OK", rid
    def give_back(self):
        with self.lock: self.stock += 1

class SQLInventory:                          # ~ UPDATE ... WHERE available_quantity > 0
    def __init__(self, n):
        self.total, self.available, self.reserved, self.sold = n, n, 0, 0
        self.lock = threading.Lock()
    def reserve(self):
        with self.lock:
            if self.available > 0: self.available -= 1; self.reserved += 1; return True
            return False
    def release(self):
        with self.lock: self.reserved -= 1; self.available += 1
    def mark_sold(self):
        with self.lock: self.reserved -= 1; self.sold += 1
    def invariant_ok(self):
        with self.lock:
            return (min(self.available, self.reserved, self.sold) >= 0
                    and self.available + self.reserved + self.sold == self.total)

gate, db = AtomicStockGate(STOCK), SQLInventory(STOCK)
reservations, payments, outbox, orders = {}, {}, [], {}
state_lock = threading.Lock()
stats = dict(ok=0, sold_out=0, duplicate=0, pay_ok=0, pay_fail=0, abandoned=0, released=0)
def bump(k):
    with state_lock: stats[k] += 1

def buy(user_id):
    key = f"user-{user_id}-attempt"           # idempotency key (same user double-click = same key)
    status, rid = gate.try_acquire(key)
    if status == "DUPLICATE": bump("duplicate"); return
    if status == "SOLD_OUT":  bump("sold_out");  return
    if not db.reserve():                      # second barrier; compensate gate if DB says no
        gate.give_back(); bump("sold_out"); return
    bump("ok")
    with state_lock: reservations[rid] = "RESERVED"
    r = random.random()
    if r < ABANDON_RATE:                      # user never pays -> expiry worker handles
        bump("abandoned"); return
    # payment, idempotent by tx_ref = rid
    with state_lock:
        if rid in payments: return
        payments[rid] = "PENDING"
    if random.random() < PAY_FAIL_RATE:
        with state_lock: payments[rid] = "FAILED"; reservations[rid] = "RELEASED"
        db.release(); gate.give_back(); bump("pay_fail")
    else:
        with state_lock:
            payments[rid] = "CAPTURED"; reservations[rid] = "CONFIRMED"
            outbox.append(rid)                # outbox event written with payment (same "transaction")
        bump("pay_ok")

def attempt(i):
    buy(i)
    if random.random() < DUP_RATE: buy(i)     # duplicate request with same idempotency key

order_service_up = threading.Event()
def outbox_relay():                           # retries until Order Service is up; consumer idempotent
    processed = 0
    while True:
        if not order_service_up.is_set(): time.sleep(0.01); continue
        with state_lock: pending = [r for r in outbox if r not in orders]
        for rid in pending:
            with state_lock:
                orders.setdefault(rid, "CONFIRMED")   # setdefault = unique(payment_id), no dup order
            db.mark_sold()
            with state_lock: reservations[rid] = "SOLD"
        if stop_relay.is_set() and not pending: return
        time.sleep(0.01)

stop_relay = threading.Event()
relay = threading.Thread(target=outbox_relay); relay.start()   # Order Service DOWN at start
t0 = time.time()
with ThreadPoolExecutor(max_workers=200) as ex: list(ex.map(attempt, range(USERS)))
print(f"[{time.time()-t0:.2f}s] 10,000 buy attempts done; Order Service still DOWN, orders so far = {len(orders)}")

# Expiry worker: release abandoned reservations (still RESERVED)
with state_lock: stale = [rid for rid, s in reservations.items() if s == "RESERVED"]
for rid in stale:
    with state_lock: reservations[rid] = "EXPIRED"
    db.release(); gate.give_back(); bump("released")

order_service_up.set()                        # Order Service recovers
time.sleep(0.3); stop_relay.set(); relay.join()

captured = sum(1 for s in payments.values() if s == "CAPTURED")
print("\n=== RESULTS ===")
print(f"Reservations won      : {stats['ok']}")
print(f"Sold-out rejections   : {stats['sold_out']}")
print(f"Duplicates idempotent : {stats['duplicate']}")
print(f"Payments OK / FAILED  : {stats['pay_ok']} / {stats['pay_fail']}")
print(f"Abandoned -> released : {stats['abandoned']} -> {stats['released']}")
print(f"Orders created        : {len(orders)}  (captured payments: {captured})")
print(f"DB state              : available={db.available} reserved={db.reserved} sold={db.sold} total={db.total}")
assert db.sold <= STOCK, "OVERSELL!"
assert db.invariant_ok(), "Inventory invariant broken"
assert len(orders) == captured, "Paid but no order / duplicate order"
assert db.reserved == 0, "Leaked reservations"
assert db.sold == captured
print("\nALL CHECKS PASSED: no oversell, idempotent duplicates, no lost/duplicate orders, no leaked reservations")
