import Link from "next/link"
import { Button } from "@/components/ui/button"
import { Play, FileQuestion } from "lucide-react"

export default function RecordingNotFound() {
  return (
    <div className="min-h-screen bg-background flex flex-col">
      <header className="border-b border-border bg-card px-4 py-3">
        <div className="container max-w-6xl mx-auto">
          <Link href="/" className="flex items-center gap-2 w-fit">
            <div className="w-8 h-8 rounded-lg bg-primary flex items-center justify-center">
              <Play className="w-4 h-4 text-primary-foreground" />
            </div>
            <span className="font-semibold">Reclip</span>
          </Link>
        </div>
      </header>

      <div className="flex-1 flex items-center justify-center px-4">
        <div className="text-center space-y-4">
          <div className="flex justify-center">
            <div className="w-20 h-20 rounded-full bg-muted flex items-center justify-center">
              <FileQuestion className="w-10 h-10 text-muted-foreground" />
            </div>
          </div>
          <h1 className="text-2xl font-semibold">Recording Not Found</h1>
          <p className="text-muted-foreground max-w-md">
            The recording you&apos;re looking for doesn&apos;t exist or may have been removed.
          </p>
          <Button asChild>
            <Link href="/">Go Home</Link>
          </Button>
        </div>
      </div>
    </div>
  )
}
