import { createClient } from "@/lib/supabase/server"
import { RecordingsList } from "@/components/recordings-list"
import { Button } from "@/components/ui/button"
import { Download } from "lucide-react"
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
      <div className="rounded-lg border border-border bg-card p-6 flex flex-col sm:flex-row items-center justify-between gap-4">
        <div>
          <h2 className="font-semibold text-lg">Get the Reclip Desktop App</h2>
          <p className="text-sm text-muted-foreground">
            Record your screen with camera overlay directly from your Mac.
          </p>
        </div>
        <Button disabled>
          <Download className="w-4 h-4" />
          Download for macOS
        </Button>
      </div>
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
