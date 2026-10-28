-- The shared documents' read limits and expiries, and the site's two counters.
--
-- The ciphertext itself is in Workers KV (the SECRETS namespace), written
-- with KV's own expiry; what KV cannot do honestly is count. KV is eventually
-- consistent, so two reads of the last remaining read in different places
-- could both see "1 left" and both be served. The counter lives here instead,
-- where one statement — UPDATE … SET remaining_reads = remaining_reads - 1
-- WHERE … remaining_reads > 0 RETURNING — decrements it atomically: of two
-- concurrent last reads, exactly one gets a row back.
--
-- remaining_reads  NULL is unlimited (the template's "0 means unlimited")
-- expires_at       epoch milliseconds, NULL for no TTL; KV expires the
--                  ciphertext at the same moment, and an expired row is
--                  refused on read and swept on the next write
-- created_at       epoch milliseconds
CREATE TABLE IF NOT EXISTS secrets (
  id              TEXT PRIMARY KEY,
  remaining_reads INTEGER,
  expires_at      INTEGER,
  created_at      INTEGER NOT NULL
);

-- The sweep on every write deletes expired rows by this column.
CREATE INDEX IF NOT EXISTS secrets_expires_at ON secrets (expires_at);

-- "Documents Encrypted" and "Documents Decrypted" on the home page (the
-- template's two Redis counters, metrics:writes and metrics:reads).
CREATE TABLE IF NOT EXISTS metrics (
  name  TEXT PRIMARY KEY,
  value INTEGER NOT NULL DEFAULT 0
);

INSERT OR IGNORE INTO metrics (name, value) VALUES ('reads', 0), ('writes', 0);
