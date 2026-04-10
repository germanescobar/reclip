import Link from "next/link"
import { Button } from "@/components/ui/button"
import { Play, Video, Share2, Gauge, Key } from "lucide-react"

export default function HomePage() {
  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="border-b border-border">
        <div className="container max-w-6xl mx-auto px-4">
          <div className="flex h-16 items-center justify-between">
            <Link href="/" className="flex items-center gap-2">
              <div className="w-8 h-8 rounded-lg bg-primary flex items-center justify-center">
                <Play className="w-4 h-4 text-primary-foreground" />
              </div>
              <span className="font-semibold">Reclip</span>
            </Link>
            <div className="flex items-center gap-3">
              <Button variant="ghost" asChild>
                <Link href="/auth/login">Sign in</Link>
              </Button>
              <Button asChild>
                <Link href="/auth/sign-up">Get Started</Link>
              </Button>
            </div>
          </div>
        </div>
      </header>

      {/* Hero */}
      <section className="py-20 lg:py-32">
        <div className="container max-w-6xl mx-auto px-4 text-center">
          <h1 className="text-4xl lg:text-6xl font-bold tracking-tight text-balance mb-6">
            Share Your Recordings
            <br />
            <span className="text-muted-foreground">With Anyone, Anywhere</span>
          </h1>
          <p className="text-xl text-muted-foreground max-w-2xl mx-auto mb-10 text-pretty">
            Store your S3 recordings and create shareable links with a custom video player. 
            Perfect for demos, tutorials, and presentations.
          </p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <Button size="lg" asChild>
              <Link href="/auth/sign-up">Start for Free</Link>
            </Button>
            <Button size="lg" variant="outline" asChild>
              <Link href="/auth/login">Sign in</Link>
            </Button>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="py-20 bg-secondary/30">
        <div className="container max-w-6xl mx-auto px-4">
          <h2 className="text-3xl font-bold text-center mb-12">
            Everything You Need
          </h2>
          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6">
            <FeatureCard
              icon={Video}
              title="Video Management"
              description="Organize and manage all your recordings in one place"
            />
            <FeatureCard
              icon={Share2}
              title="Instant Sharing"
              description="Generate shareable links for any recording instantly"
            />
            <FeatureCard
              icon={Gauge}
              title="Playback Controls"
              description="Watch at your own pace with adjustable playback speeds"
            />
            <FeatureCard
              icon={Key}
              title="API Access"
              description="Programmatically add recordings via our REST API"
            />
          </div>
        </div>
      </section>

      {/* API Section */}
      <section className="py-20">
        <div className="container max-w-6xl mx-auto px-4">
          <div className="grid lg:grid-cols-2 gap-12 items-center">
            <div>
              <h2 className="text-3xl font-bold mb-4">
                Developer-Friendly API
              </h2>
              <p className="text-muted-foreground mb-6">
                Integrate Reclip into your workflow with our simple REST API. 
                Generate API keys and start adding recordings programmatically.
              </p>
              <Button asChild>
                <Link href="/auth/sign-up">Get Your API Key</Link>
              </Button>
            </div>
            <div className="rounded-lg bg-secondary p-6 font-mono text-sm overflow-x-auto">
              <pre className="text-foreground">{`curl -X POST https://your-domain.com/api/recordings \\
  -H "Authorization: Bearer YOUR_API_KEY" \\
  -H "Content-Type: application/json" \\
  -d '{
    "title": "My Recording",
    "description": "Optional description",
    "s3_url": "https://bucket.s3.amazonaws.com/video.mp4"
  }'`}</pre>
            </div>
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="py-20 bg-primary text-primary-foreground">
        <div className="container max-w-6xl mx-auto px-4 text-center">
          <h2 className="text-3xl font-bold mb-4">
            Ready to Get Started?
          </h2>
          <p className="text-primary-foreground/80 mb-8 max-w-xl mx-auto">
            Create your free account and start sharing your recordings today.
          </p>
          <Button size="lg" variant="secondary" asChild>
            <Link href="/auth/sign-up">Create Free Account</Link>
          </Button>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-border py-8">
        <div className="container max-w-6xl mx-auto px-4">
          <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
            <div className="flex items-center gap-2">
              <div className="w-6 h-6 rounded bg-primary flex items-center justify-center">
                <Play className="w-3 h-3 text-primary-foreground" />
              </div>
              <span className="text-sm text-muted-foreground">Reclip</span>
            </div>
            <p className="text-sm text-muted-foreground">
              Built with Next.js and Supabase
            </p>
          </div>
        </div>
      </footer>
    </div>
  )
}

function FeatureCard({
  icon: Icon,
  title,
  description,
}: {
  icon: React.ElementType
  title: string
  description: string
}) {
  return (
    <div className="rounded-lg border border-border bg-card p-6">
      <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center mb-4">
        <Icon className="w-5 h-5 text-primary" />
      </div>
      <h3 className="font-semibold mb-2">{title}</h3>
      <p className="text-sm text-muted-foreground">{description}</p>
    </div>
  )
}
