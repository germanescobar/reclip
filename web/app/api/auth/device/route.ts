import { createClient } from "@/lib/supabase/server"
import { NextResponse } from "next/server"
import { generateApiKey, hashApiKey } from "@/lib/utils/api-keys"

export async function POST(request: Request) {
  try {
    const supabase = await createClient()
    const { data: { user } } = await supabase.auth.getUser()

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
    }

    const body = await request.json()
    const { session_token } = body

    if (!session_token || typeof session_token !== "string") {
      return NextResponse.json({ error: "Missing session_token" }, { status: 400 })
    }

    const apiKey = generateApiKey()
    const keyHash = hashApiKey(apiKey)
    const keyPrefix = apiKey.substring(0, 12)

    const { error } = await supabase
      .from("api_keys")
      .insert({
        user_id: user.id,
        key_hash: keyHash,
        key_prefix: keyPrefix,
        name: "Reclip Desktop",
      })

    if (error) {
      console.error("Error creating API key:", error)
      return NextResponse.json({ error: "Failed to create API key" }, { status: 500 })
    }

    return NextResponse.json({ api_key: apiKey })
  } catch {
    return NextResponse.json({ error: "Internal server error" }, { status: 500 })
  }
}
