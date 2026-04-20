"use client"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { createClient } from "@/lib/supabase/client"
import type { Recording } from "@/lib/types"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Video, MoreVertical, Pencil, Trash2, Link2, ExternalLink } from "lucide-react"
import { Empty } from "@/components/ui/empty"

interface RecordingsListProps {
  recordings: Recording[]
}

export function RecordingsList({ recordings: initialRecordings }: RecordingsListProps) {
  const [recordings, setRecordings] = useState(initialRecordings)
  const [editingRecording, setEditingRecording] = useState<Recording | null>(null)
  const [deletingRecording, setDeletingRecording] = useState<Recording | null>(null)
  const [isUpdating, setIsUpdating] = useState(false)
  const [isDeleting, setIsDeleting] = useState(false)
  const [copiedId, setCopiedId] = useState<string | null>(null)
  const router = useRouter()
  const supabase = createClient()

  const copyShareLink = async (shortId: string) => {
    const url = `${window.location.origin}/r/${shortId}`
    await navigator.clipboard.writeText(url)
    setCopiedId(shortId)
    setTimeout(() => setCopiedId(null), 2000)
  }

  const handleUpdate = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    if (!editingRecording) return

    setIsUpdating(true)
    const formData = new FormData(e.currentTarget)
    const title = formData.get("title") as string
    const description = formData.get("description") as string

    const { error } = await supabase
      .from("recordings")
      .update({ title, description })
      .eq("id", editingRecording.id)

    if (!error) {
      setRecordings((prev) =>
        prev.map((r) =>
          r.id === editingRecording.id ? { ...r, title, description } : r
        )
      )
      setEditingRecording(null)
      router.refresh()
    }
    setIsUpdating(false)
  }

  const handleDelete = async () => {
    if (!deletingRecording) return

    setIsDeleting(true)
    const { error } = await supabase
      .from("recordings")
      .delete()
      .eq("id", deletingRecording.id)

    if (!error) {
      setRecordings((prev) => prev.filter((r) => r.id !== deletingRecording.id))
      setDeletingRecording(null)
      router.refresh()
    }
    setIsDeleting(false)
  }

  if (recordings.length === 0) {
    return (
      <Card>
        <CardContent className="py-12">
          <Empty
            icon={Video}
            title="No recordings yet"
            description="Use the API to add your first recording. Check the API Keys section to get started."
          />
        </CardContent>
      </Card>
    )
  }

  return (
    <>
      <div className="grid gap-4">
        {recordings.map((recording) => (
          <Card
            key={recording.id}
            className="cursor-pointer transition-colors hover:bg-accent/50"
            onClick={() => router.push(`/r/${recording.short_id}`)}
          >
            <CardHeader className="flex flex-row items-start justify-between space-y-0 pb-2">
              <div className="space-y-1 min-w-0 flex-1 pr-4">
                <CardTitle className="text-lg truncate">{recording.title}</CardTitle>
                {recording.description && (
                  <CardDescription className="line-clamp-2">
                    {recording.description}
                  </CardDescription>
                )}
              </div>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="ghost" size="icon" className="shrink-0" onClick={(e) => e.stopPropagation()}>
                    <MoreVertical className="w-4 h-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" onClick={(e) => e.stopPropagation()}>
                  <DropdownMenuItem onClick={() => copyShareLink(recording.short_id)}>
                    <Link2 className="w-4 h-4 mr-2" />
                    {copiedId === recording.short_id ? "Copied!" : "Copy share link"}
                  </DropdownMenuItem>
                  <DropdownMenuItem asChild>
                    <a href={`/r/${recording.short_id}`} target="_blank" rel="noopener noreferrer">
                      <ExternalLink className="w-4 h-4 mr-2" />
                      Open recording
                    </a>
                  </DropdownMenuItem>
                  <DropdownMenuItem onClick={() => setEditingRecording(recording)}>
                    <Pencil className="w-4 h-4 mr-2" />
                    Edit
                  </DropdownMenuItem>
                  <DropdownMenuItem
                    onClick={() => setDeletingRecording(recording)}
                    className="text-destructive"
                  >
                    <Trash2 className="w-4 h-4 mr-2" />
                    Delete
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </CardHeader>
            <CardContent>
              {recording.transcript_text && (
                <p className="mb-3 line-clamp-2 text-sm text-muted-foreground">
                  {recording.transcript_text}
                </p>
              )}
              <div className="flex items-center gap-4 text-sm text-muted-foreground">
                <span>
                  Created {new Date(recording.created_at).toLocaleDateString()}
                </span>
                {recording.transcript_text && (
                  <span className="rounded-full bg-secondary px-2 py-0.5 text-xs font-medium">
                    Transcript
                  </span>
                )}
                <span className="font-mono bg-secondary px-2 py-0.5 rounded text-xs">
                  /r/{recording.short_id}
                </span>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Edit Dialog */}
      <Dialog open={!!editingRecording} onOpenChange={() => setEditingRecording(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit Recording</DialogTitle>
            <DialogDescription>
              Update the title and description of your recording.
            </DialogDescription>
          </DialogHeader>
          <form onSubmit={handleUpdate}>
            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="title">Title</Label>
                <Input
                  id="title"
                  name="title"
                  defaultValue={editingRecording?.title}
                  required
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="description">Description</Label>
                <Textarea
                  id="description"
                  name="description"
                  defaultValue={editingRecording?.description || ""}
                  rows={3}
                />
              </div>
            </div>
            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => setEditingRecording(null)}
              >
                Cancel
              </Button>
              <Button type="submit" disabled={isUpdating}>
                {isUpdating ? "Saving..." : "Save changes"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Delete Dialog */}
      <Dialog open={!!deletingRecording} onOpenChange={() => setDeletingRecording(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete Recording</DialogTitle>
            <DialogDescription>
              Are you sure you want to delete &quot;{deletingRecording?.title}&quot;? This action
              cannot be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setDeletingRecording(null)}
            >
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={handleDelete}
              disabled={isDeleting}
            >
              {isDeleting ? "Deleting..." : "Delete"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}
