# Multi-Destination Backups

Back up to multiple destinations for redundancy.

---

## Modes

- **Sequential**: one destination at a time (stable, lower load)
- **Parallel**: all destinations at once (fast, higher load)

---

## Setup

1. Add multiple destinations in **Save To**
2. Choose **Copy Mode** (sequential/parallel)
3. Drag to reorder priority

---

## Behavior

- Each destination tracks its own progress
- If one destination fails, others continue

---

## Related

- [Stop](./stop.md)
- [Push Notifications](./push-notifications.md)
