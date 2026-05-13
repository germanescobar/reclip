export interface TranscriptSegment {
  id: number
  start: number
  end: number
  text: string
}

export interface Recording {
  id: string
  user_id: string
  short_id: string
  title: string
  description: string | null
  s3_url: string
  transcript_text: string | null
  transcript_segments: TranscriptSegment[] | null
  created_at: string
  updated_at: string
}

export interface ApiKey {
  id: string
  user_id: string
  key_hash: string
  key_prefix: string
  name: string
  created_at: string
  last_used_at: string | null
}
