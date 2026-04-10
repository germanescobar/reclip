import { createClient } from "@/lib/supabase/server"
import { RecordingsList } from "@/components/recordings-list"
import type { Recording } from "@/lib/types"

export default async function DashboardPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) return null

  const { data: recordings } = await supabase
    .from("recordings")
    .select("*")
    .eq("user_id", user.id)
    .order("created_at", { ascending: false })

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Your Recordings</h1>
        <p className="text-muted-foreground">
          Manage and share your recordings
        </p>
      </div>
      <RecordingsList recordings={(recordings as Recording[]) || []} />
    </div>
  )
}
