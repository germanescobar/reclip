import { createClient } from '@supabase/supabase-js'

/**
 * Creates a Supabase client with the service role key.
 * This bypasses RLS and should only be used in server-side API routes
 * where authentication is handled separately (e.g., API key auth).
 */
export function createAdminClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
  )
}
