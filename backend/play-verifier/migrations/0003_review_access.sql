CREATE TABLE review_installations (
  credential_hash TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  revoked_at_ms INTEGER
);
CREATE INDEX review_installations_device ON review_installations(device_id);
