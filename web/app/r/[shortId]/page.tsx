import { createClient } from "@/lib/supabase/server"
import { createAdminClient } from "@/lib/supabase/admin"
import { notFound } from "next/navigation"
import { VideoPlayer } from "@/components/video-player"
import type { Recording } from "@/lib/types"
import type { Metadata } from "next"

interface PageProps {
  params: Promise<{ shortId: string }>
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { shortId } = await params
  const supabase = await createClient()

  const { data: recording } = await supabase
    .from("recordings")
    .select("*")
    .eq("short_id", shortId)
    .single()

  if (!recording) {
    return { title: "Recording Not Found" }
  }

  return {
    title: `${recording.title} - Reclip`,
    description: recording.description || `Watch ${recording.title} on Reclip`,
  }
}

export default async function RecordingPage({ params }: PageProps) {
  const { shortId } = await params
  const supabase = await createClient()

  const { data: recording } = await supabase
    .from("recordings")
    .select("*")
    .eq("short_id", shortId)
    .single()

  if (!recording) {
    notFound()
  }

  const { data: { user } } = await supabase.auth.getUser()

  // Fetch the recording owner's info
  let ownerName: string | undefined
  try {
    const admin = createAdminClient()
    const { data: ownerData } = await admin.auth.admin.getUserById(recording.user_id)
    const owner = ownerData?.user
    ownerName = owner?.user_metadata?.full_name || owner?.email
  } catch {
    // Ignore - we'll just not show owner info
  }

  return (
    <div className="min-h-screen bg-background">
      <VideoPlayer
        recording={recording as Recording}
        isLoggedIn={!!user}
        ownerName={ownerName}
      />
    </div>
  )
}
