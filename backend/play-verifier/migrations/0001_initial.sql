-- Hashes only: do not persist raw Google Play purchase tokens.
CREATE TABLE IF NOT EXISTS revoked_purchase_tokens (
  token_hash TEXT PRIMARY KEY NOT NULL,
  voided_at_ms INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sync_state (
  key TEXT PRIMARY KEY NOT NULL,
  completed_at_ms INTEGER NOT NULL
);
