"use client"

import { useState, useEffect } from "react"
import { createClient } from "@/lib/supabase/client"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import { Check } from "lucide-react"

export default function ProfilePage() {
  const supabase = createClient()
  const [fullName, setFullName] = useState("")
  const [email, setEmail] = useState("")
  const [loading, setLoading] = useState(false)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const loadUser = async () => {
      const { data: { user } } = await supabase.auth.getUser()
      if (user) {
        setFullName(user.user_metadata?.full_name ?? "")
        setEmail(user.email ?? "")
      }
    }
    loadUser()
  }, [supabase.auth])

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError(null)
    setSaved(false)

    const { error } = await supabase.auth.updateUser({
      data: { full_name: fullName },
    })

    if (error) {
      setError(error.message)
    } else {
      setSaved(true)
      setTimeout(() => setSaved(false), 3000)
    }
    setLoading(false)
  }

  const initial = (fullName[0] || email[0] || "?").toUpperCase()

  return (
    <div className="max-w-2xl">
      <h1 className="text-2xl font-semibold mb-6">Profile</h1>

      <Card>
        <CardHeader>
          <div className="flex items-center gap-4">
            <Avatar className="size-14">
              <AvatarFallback className="bg-primary text-primary-foreground text-lg font-medium">
                {initial}
              </AvatarFallback>
            </Avatar>
            <div>
              <CardTitle>{fullName || email}</CardTitle>
              <CardDescription>{email}</CardDescription>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSave} className="space-y-4">
            {error && (
              <div className="p-3 rounded-md bg-destructive/10 text-destructive text-sm">
                {error}
              </div>
            )}
            <div className="space-y-2">
              <Label htmlFor="fullName">Full Name</Label>
              <Input
                id="fullName"
                type="text"
                placeholder="Your name"
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                value={email}
                disabled
                className="bg-muted"
              />
              <p className="text-xs text-muted-foreground">Email cannot be changed.</p>
            </div>
            <Button type="submit" disabled={loading} className="gap-2">
              {saved ? (
                <>
                  <Check className="w-4 h-4" />
                  Saved
                </>
              ) : loading ? (
                "Saving..."
              ) : (
                "Save changes"
              )}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
