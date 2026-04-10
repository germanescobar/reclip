-- Create recordings table
CREATE TABLE IF NOT EXISTS recordings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  short_id VARCHAR(8) UNIQUE NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  s3_url TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create api_keys table
CREATE TABLE IF NOT EXISTS api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  key_hash TEXT NOT NULL,
  key_prefix VARCHAR(12) NOT NULL,
  name TEXT NOT NULL DEFAULT 'Default',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_used_at TIMESTAMPTZ,
  UNIQUE(user_id, key_hash)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_recordings_user_id ON recordings(user_id);
CREATE INDEX IF NOT EXISTS idx_recordings_short_id ON recordings(short_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_user_id ON api_keys(user_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_key_hash ON api_keys(key_hash);

-- Enable RLS on recordings
ALTER TABLE recordings ENABLE ROW LEVEL SECURITY;

-- RLS Policies for recordings
-- Users can view their own recordings
CREATE POLICY "Users can view own recordings" ON recordings
  FOR SELECT USING (auth.uid() = user_id);

-- Anyone can view recordings by short_id (public access for sharing)
CREATE POLICY "Public can view recordings by short_id" ON recordings
  FOR SELECT USING (true);

-- Users can insert their own recordings
CREATE POLICY "Users can insert own recordings" ON recordings
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Users can update their own recordings
CREATE POLICY "Users can update own recordings" ON recordings
  FOR UPDATE USING (auth.uid() = user_id);

-- Users can delete their own recordings
CREATE POLICY "Users can delete own recordings" ON recordings
  FOR DELETE USING (auth.uid() = user_id);

-- Enable RLS on api_keys
ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;

-- RLS Policies for api_keys
-- Users can only view their own API keys
CREATE POLICY "Users can view own api_keys" ON api_keys
  FOR SELECT USING (auth.uid() = user_id);

-- Users can insert their own API keys
CREATE POLICY "Users can insert own api_keys" ON api_keys
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Users can delete their own API keys
CREATE POLICY "Users can delete own api_keys" ON api_keys
  FOR DELETE USING (auth.uid() = user_id);

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger for recordings updated_at
DROP TRIGGER IF EXISTS update_recordings_updated_at ON recordings;
CREATE TRIGGER update_recordings_updated_at
  BEFORE UPDATE ON recordings
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
