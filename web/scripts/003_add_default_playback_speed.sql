-- Adds a per-recording default playback speed that the owner can configure.
-- The web viewer and the macOS upload flow both fall back to 1.5x when this
-- column is NULL, so existing rows are unaffected and the feature can be
-- rolled out without a backfill.

ALTER TABLE recordings
  ADD COLUMN IF NOT EXISTS default_playback_speed NUMERIC(4, 2)
    CHECK (default_playback_speed IS NULL OR default_playback_speed > 0);
