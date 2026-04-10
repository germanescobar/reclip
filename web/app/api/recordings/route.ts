import { createAdminClient } from "@/lib/supabase/admin"
import { NextResponse } from "next/server"
import crypto from "crypto"
import { generateShortId } from "@/lib/utils/short-id"

function hashApiKey(key: string): string {
  return crypto.createHash("sha256").update(key).digest("hex")
}

export async function POST(request: Request) {
  try {
    // Get the API key from Authorization header
    const authHeader = request.headers.get("Authorization")
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return NextResponse.json(
        { error: "Missing or invalid Authorization header" },
        { status: 401 }
      )
    }

    const apiKey = authHeader.substring(7) // Remove "Bearer " prefix
    const keyHash = hashApiKey(apiKey)

    const supabase = createAdminClient()

    // Find the API key and get the user_id
    const { data: apiKeyRecord, error: keyError } = await supabase
      .from("api_keys")
      .select("id, user_id")
      .eq("key_hash", keyHash)
      .single()

    if (keyError || !apiKeyRecord) {
      return NextResponse.json(
        { error: "Invalid API key" },
        { status: 401 }
      )
    }

    // Update last_used_at
    await supabase
      .from("api_keys")
      .update({ last_used_at: new Date().toISOString() })
      .eq("id", apiKeyRecord.id)

    // Parse the request body
    const body = await request.json()
    const { title, description, s3_url } = body

    if (!title || typeof title !== "string") {
      return NextResponse.json(
        { error: "Title is required" },
        { status: 400 }
      )
    }

    if (!s3_url || typeof s3_url !== "string") {
      return NextResponse.json(
        { error: "s3_url is required" },
        { status: 400 }
      )
    }

    // Validate URL format
    try {
      new URL(s3_url)
    } catch {
      return NextResponse.json(
        { error: "Invalid s3_url format" },
        { status: 400 }
      )
    }

    // Generate a unique short ID
    let shortId = generateShortId()
    let attempts = 0
    const maxAttempts = 5

    // Check for collision and regenerate if needed
    while (attempts < maxAttempts) {
      const { data: existing } = await supabase
        .from("recordings")
        .select("id")
        .eq("short_id", shortId)
        .single()

      if (!existing) break

      shortId = generateShortId()
      attempts++
    }

    if (attempts >= maxAttempts) {
      return NextResponse.json(
        { error: "Failed to generate unique short ID" },
        { status: 500 }
      )
    }

    // Create the recording
    const { data: recording, error: insertError } = await supabase
      .from("recordings")
      .insert({
        user_id: apiKeyRecord.user_id,
        short_id: shortId,
        title: title.trim(),
        description: description?.trim() || null,
        s3_url,
      })
      .select()
      .single()

    if (insertError) {
      console.error("Error creating recording:", insertError)
      return NextResponse.json(
        { error: "Failed to create recording" },
        { status: 500 }
      )
    }

    // Get the base URL for the shareable link
    const baseUrl = request.headers.get("origin") || request.headers.get("host") || ""
    const protocol = baseUrl.includes("localhost") ? "http" : "https"
    const shareableUrl = baseUrl.startsWith("http")
      ? `${baseUrl}/r/${shortId}`
      : `${protocol}://${baseUrl}/r/${shortId}`

    return NextResponse.json({
      success: true,
      recording: {
        id: recording.id,
        short_id: recording.short_id,
        title: recording.title,
        description: recording.description,
        created_at: recording.created_at,
      },
      shareable_url: shareableUrl,
    })
  } catch (error) {
    console.error("API error:", error)
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    )
  }
}
