"use client"

import { Suspense, useState } from "react"
import { createClient } from "@/lib/supabase/client"
import Link from "next/link"
import { useSearchParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card"
import { Play, CheckCircle } from "lucide-react"

export default function DeviceLoginPage() {
  return (
    <Suspense>
      <DeviceLoginContent />
    </Suspense>
  )
}

function DeviceLoginContent() {
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [completed, setCompleted] = useState(false)
  const searchParams = useSearchParams()
  const sessionToken = searchParams.get("session_token")
  const supabase = createClient()

  if (!sessionToken) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background px-4">
        <Card className="w-full max-w-md">
          <CardHeader className="text-center">
            <CardTitle className="text-2xl">Invalid Link</CardTitle>
            <CardDescription>
              This page should be opened from the Reclip desktop app.
            </CardDescription>
          </CardHeader>
        </Card>
      </div>
    )
  }

  if (completed) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background px-4">
        <Card className="w-full max-w-md">
          <CardHeader className="text-center">
            <div className="flex justify-center mb-4">
              <CheckCircle className="w-12 h-12 text-green-500" />
            </div>
            <CardTitle className="text-2xl">Signed In</CardTitle>
            <CardDescription>
              You have been signed in to the Reclip desktop app. You can close this tab.
            </CardDescription>
          </CardHeader>
        </Card>
      </div>
    )
  }

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError(null)

    const { error: authError } = await supabase.auth.signInWithPassword({
      email,
      password,
    })

    if (authError) {
      setError(authError.message)
      setLoading(false)
      return
    }

    try {
      const response = await fetch("/api/auth/device", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ session_token: sessionToken }),
      })

      if (!response.ok) {
        const data = await response.json()
        setError(data.error || "Failed to complete sign in")
        setLoading(false)
        return
      }

      const { api_key } = await response.json()

      const callbackUrl = `reclip://auth/callback?api_key=${encodeURIComponent(api_key)}&session_token=${encodeURIComponent(sessionToken)}`
      window.location.href = callbackUrl
      setCompleted(true)
    } catch {
      setError("Failed to complete sign in")
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-background px-4">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center">
          <div className="flex justify-center mb-4">
            <div className="flex items-center gap-2">
              <div className="w-10 h-10 rounded-lg bg-primary flex items-center justify-center">
                <Play className="w-5 h-5 text-primary-foreground" />
              </div>
              <span className="text-xl font-semibold">Reclip</span>
            </div>
          </div>
          <CardTitle className="text-2xl">Sign in to Reclip Desktop</CardTitle>
          <CardDescription>
            Sign in to connect your Reclip desktop app
          </CardDescription>
        </CardHeader>
        <form onSubmit={handleLogin}>
          <CardContent className="space-y-4">
            {error && (
              <div className="p-3 rounded-md bg-destructive/10 text-destructive text-sm">
                {error}
              </div>
            )}
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                placeholder="you@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                type="password"
                placeholder="Your password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </div>
          </CardContent>
          <CardFooter className="flex flex-col gap-4">
            <Button type="submit" className="w-full" disabled={loading}>
              {loading ? "Signing in..." : "Sign in"}
            </Button>
            <p className="text-sm text-muted-foreground text-center">
              {"Don't have an account? "}
              <Link href={`/auth/sign-up?redirect=/auth/device-login?session_token=${sessionToken}`} className="text-primary hover:underline">
                Sign up
              </Link>
            </p>
          </CardFooter>
        </form>
      </Card>
    </div>
  )
}
