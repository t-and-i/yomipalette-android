-- Server-owned first-use time. A reinstall or local-data wipe cannot reset it.
-- subject_key is an HMAC of Google's stable sub (not email or raw sub).
CREATE TABLE IF NOT EXISTS trial_entitlements (
  subject_key TEXT PRIMARY KEY NOT NULL,
  started_at_ms INTEGER NOT NULL,
  expires_at_ms INTEGER NOT NULL,
  last_verified_at_ms INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'blocked'))
);
CREATE INDEX IF NOT EXISTS idx_trial_entitlements_expiry
  ON trial_entitlements (expires_at_ms);
