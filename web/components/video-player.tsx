"use client"

import { useRef, useState, useEffect, useCallback } from "react"
import Link from "next/link"
import type { Recording } from "@/lib/types"
import { Button } from "@/components/ui/button"
import { Slider } from "@/components/ui/slider"
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import {
  Play,
  Pause,
  Volume2,
  VolumeX,
  Maximize,
  Minimize,
  Settings,
  Check,
  Link as LinkIcon,
} from "lucide-react"
import { cn } from "@/lib/utils"
import { formatDistanceToNow } from "date-fns"

interface VideoPlayerProps {
  recording: Recording
  isLoggedIn?: boolean
  ownerName?: string
}

const PLAYBACK_SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
const DEFAULT_PLAYBACK_SPEED = 1.5

export function VideoPlayer({ recording, isLoggedIn, ownerName }: VideoPlayerProps) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const containerRef = useRef<HTMLDivElement>(null)
  const [isPlaying, setIsPlaying] = useState(false)
  const [currentTime, setCurrentTime] = useState(0)
  const [duration, setDuration] = useState(0)
  const [volume, setVolume] = useState(1)
  const [isMuted, setIsMuted] = useState(false)
  const [isFullscreen, setIsFullscreen] = useState(false)
  const [playbackSpeed, setPlaybackSpeed] = useState(DEFAULT_PLAYBACK_SPEED)
  const [showControls, setShowControls] = useState(true)
  const [isBuffering, setIsBuffering] = useState(false)
  const [linkCopied, setLinkCopied] = useState(false)
  const controlsTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const ownerDisplayName = ownerName ?? "Unknown"
  const ownerInitial = (ownerDisplayName[0] ?? "?").toUpperCase()
  const sharedTimeAgo = formatDistanceToNow(new Date(recording.created_at), { addSuffix: true })

  const handleCopyLink = async () => {
    await navigator.clipboard.writeText(window.location.href)
    setLinkCopied(true)
    setTimeout(() => setLinkCopied(false), 2000)
  }

  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60)
    const secs = Math.floor(seconds % 60)
    return `${mins}:${secs.toString().padStart(2, "0")}`
  }

  const handlePlayPause = () => {
    if (videoRef.current) {
      if (isPlaying) {
        videoRef.current.pause()
      } else {
        videoRef.current.play()
      }
    }
  }

  const handleSeek = (value: number[]) => {
    if (videoRef.current) {
      videoRef.current.currentTime = value[0]
      setCurrentTime(value[0])
    }
  }

  const handleVolumeChange = (value: number[]) => {
    const newVolume = value[0]
    setVolume(newVolume)
    if (videoRef.current) {
      videoRef.current.volume = newVolume
      setIsMuted(newVolume === 0)
    }
  }

  const toggleMute = () => {
    if (videoRef.current) {
      videoRef.current.muted = !isMuted
      setIsMuted(!isMuted)
    }
  }

  const handleSpeedChange = (speed: number) => {
    setPlaybackSpeed(speed)
    if (videoRef.current) {
      videoRef.current.playbackRate = speed
    }
  }

  const toggleFullscreen = async () => {
    if (!isFullscreen) {
      if (containerRef.current?.requestFullscreen) {
        await containerRef.current.requestFullscreen()
      } else if (videoRef.current && "webkitEnterFullscreen" in videoRef.current) {
        (videoRef.current as HTMLVideoElement & { webkitEnterFullscreen: () => void }).webkitEnterFullscreen()
      }
    } else {
      if (document.exitFullscreen) {
        await document.exitFullscreen()
      }
    }
  }

  const handleMouseMove = useCallback(() => {
    setShowControls(true)
    if (controlsTimeoutRef.current) {
      clearTimeout(controlsTimeoutRef.current)
    }
    if (isPlaying) {
      controlsTimeoutRef.current = setTimeout(() => {
        setShowControls(false)
      }, 3000)
    }
  }, [isPlaying])

  useEffect(() => {
    const video = videoRef.current
    if (!video) return

    video.playbackRate = DEFAULT_PLAYBACK_SPEED

    const handlePlay = () => setIsPlaying(true)
    const handlePause = () => setIsPlaying(false)
    const handleTimeUpdate = () => setCurrentTime(video.currentTime)
    const handleLoadedMetadata = () => setDuration(video.duration)
    const handleWaiting = () => setIsBuffering(true)
    const handleCanPlay = () => setIsBuffering(false)

    video.addEventListener("play", handlePlay)
    video.addEventListener("pause", handlePause)
    video.addEventListener("timeupdate", handleTimeUpdate)
    video.addEventListener("loadedmetadata", handleLoadedMetadata)
    video.addEventListener("waiting", handleWaiting)
    video.addEventListener("canplay", handleCanPlay)

    return () => {
      video.removeEventListener("play", handlePlay)
      video.removeEventListener("pause", handlePause)
      video.removeEventListener("timeupdate", handleTimeUpdate)
      video.removeEventListener("loadedmetadata", handleLoadedMetadata)
      video.removeEventListener("waiting", handleWaiting)
      video.removeEventListener("canplay", handleCanPlay)
    }
  }, [])

  useEffect(() => {
    const handleFullscreenChange = () => {
      setIsFullscreen(!!document.fullscreenElement)
    }

    document.addEventListener("fullscreenchange", handleFullscreenChange)
    document.addEventListener("webkitfullscreenchange", handleFullscreenChange)

    const video = videoRef.current
    const handleWebkitEnd = () => setIsFullscreen(false)
    video?.addEventListener("webkitendfullscreen", handleWebkitEnd)

    return () => {
      document.removeEventListener("fullscreenchange", handleFullscreenChange)
      document.removeEventListener("webkitfullscreenchange", handleWebkitEnd)
      video?.removeEventListener("webkitendfullscreen", handleWebkitEnd)
    }
  }, [])

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return

      switch (e.key) {
        case " ":
        case "k":
          e.preventDefault()
          handlePlayPause()
          break
        case "m":
          toggleMute()
          break
        case "f":
          toggleFullscreen()
          break
        case "ArrowLeft":
          if (videoRef.current) {
            videoRef.current.currentTime = Math.max(0, videoRef.current.currentTime - 10)
          }
          break
        case "ArrowRight":
          if (videoRef.current) {
            videoRef.current.currentTime = Math.min(duration, videoRef.current.currentTime + 10)
          }
          break
      }
    }

    window.addEventListener("keydown", handleKeyDown)
    return () => window.removeEventListener("keydown", handleKeyDown)
  }, [duration])

  return (
    <div className="min-h-screen flex flex-col bg-background">
      {/* Header */}
      <header className="border-b border-border bg-card px-4 py-3">
        <div className="flex items-center justify-between">
          <Link href="/" className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-lg bg-primary flex items-center justify-center">
              <Play className="w-4 h-4 text-primary-foreground" />
            </div>
            <span className="font-semibold">Reclip</span>
          </Link>

          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              size="sm"
              className="gap-1.5"
              onClick={handleCopyLink}
            >
              {linkCopied ? (
                <>
                  <Check className="w-3.5 h-3.5" />
                  Copied!
                </>
              ) : (
                <>
                  <LinkIcon className="w-3.5 h-3.5" />
                  Copy link
                </>
              )}
            </Button>
            {isLoggedIn && (
              <Link href="/dashboard">
                <Button size="sm">Go to Dashboard</Button>
              </Link>
            )}
          </div>
        </div>
      </header>

      {/* Main Content */}
      <div className="flex-1 flex flex-col lg:flex-row">
        {/* Video Area */}
        <div className="flex-1 p-4 lg:p-6">
          <div
            ref={containerRef}
            className="relative w-full aspect-video rounded-xl overflow-hidden bg-black shadow-lg"
            onMouseMove={handleMouseMove}
            onMouseLeave={() => isPlaying && setShowControls(false)}
          >
            <video
              ref={videoRef}
              src={recording.s3_url}
              className="w-full h-full object-contain"
              onClick={handlePlayPause}
              playsInline
            />

            {/* Buffering Indicator */}
            {isBuffering && (
              <div className="absolute inset-0 flex items-center justify-center bg-black/30">
                <div className="w-12 h-12 border-4 border-white/30 border-t-white rounded-full animate-spin" />
              </div>
            )}

            {/* Play Button Overlay */}
            {!isPlaying && !isBuffering && (
              <button
                onClick={handlePlayPause}
                className="absolute inset-0 flex items-center justify-center bg-black/20 transition-opacity"
              >
                <div className="w-16 h-16 rounded-full bg-primary/90 flex items-center justify-center shadow-xl backdrop-blur-sm">
                  <Play className="w-7 h-7 text-primary-foreground ml-0.5" />
                </div>
              </button>
            )}

            {/* Controls */}
            <div
              className={cn(
                "absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/80 via-black/40 to-transparent px-4 pb-3 pt-10 transition-opacity duration-300",
                showControls ? "opacity-100" : "opacity-0 pointer-events-none"
              )}
            >
              {/* Progress Bar */}
              <div className="mb-3">
                <Slider
                  value={[currentTime]}
                  max={duration || 100}
                  step={0.1}
                  onValueChange={handleSeek}
                  className="cursor-pointer"
                />
              </div>

              {/* Control Buttons */}
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-1.5">
                  <Button
                    variant="ghost"
                    size="icon"
                    onClick={handlePlayPause}
                    className="text-white hover:bg-white/20 h-8 w-8"
                  >
                    {isPlaying ? (
                      <Pause className="w-4 h-4" />
                    ) : (
                      <Play className="w-4 h-4" />
                    )}
                  </Button>

                  <div className="flex items-center gap-1 group">
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={toggleMute}
                      className="text-white hover:bg-white/20 h-8 w-8"
                    >
                      {isMuted || volume === 0 ? (
                        <VolumeX className="w-4 h-4" />
                      ) : (
                        <Volume2 className="w-4 h-4" />
                      )}
                    </Button>
                    <div className="w-0 overflow-hidden group-hover:w-20 transition-all duration-200">
                      <Slider
                        value={[isMuted ? 0 : volume]}
                        max={1}
                        step={0.05}
                        onValueChange={handleVolumeChange}
                        className="cursor-pointer"
                      />
                    </div>
                  </div>

                  <span className="text-white/90 text-xs ml-1 tabular-nums">
                    {formatTime(currentTime)} / {formatTime(duration)}
                  </span>
                </div>

                <div className="flex items-center gap-1">
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button
                        variant="ghost"
                        size="sm"
                        className="text-white hover:bg-white/20 gap-1 h-8 px-2"
                      >
                        <Settings className="w-3.5 h-3.5" />
                        <span className="text-xs">{playbackSpeed}x</span>
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      {PLAYBACK_SPEEDS.map((speed) => (
                        <DropdownMenuItem
                          key={speed}
                          onClick={() => handleSpeedChange(speed)}
                          className="flex items-center justify-between"
                        >
                          {speed}x
                          {playbackSpeed === speed && (
                            <Check className="w-4 h-4 ml-2" />
                          )}
                        </DropdownMenuItem>
                      ))}
                    </DropdownMenuContent>
                  </DropdownMenu>

                  <Button
                    variant="ghost"
                    size="icon"
                    onClick={toggleFullscreen}
                    className="text-white hover:bg-white/20 h-8 w-8"
                  >
                    {isFullscreen ? (
                      <Minimize className="w-4 h-4" />
                    ) : (
                      <Maximize className="w-4 h-4" />
                    )}
                  </Button>
                </div>
              </div>
            </div>
          </div>

          {/* Title & Description below video */}
          <div className="mt-4 px-1">
            <h1 className="text-lg font-semibold text-balance">{recording.title}</h1>
            {recording.description && (
              <p className="text-sm text-muted-foreground mt-1">{recording.description}</p>
            )}
          </div>
        </div>

        {/* Sidebar */}
        <div className="lg:w-80 xl:w-96 border-t lg:border-t-0 lg:border-l border-border bg-card p-5">
          <div className="flex items-center gap-3 mb-4">
            <Avatar className="size-10">
              <AvatarFallback className="bg-primary text-primary-foreground font-medium">
                {ownerInitial}
              </AvatarFallback>
            </Avatar>
            <div>
              <div className="text-sm font-medium">{ownerDisplayName}</div>
              <div className="text-xs text-muted-foreground">Shared {sharedTimeAgo}</div>
            </div>
          </div>
          <div className="border-t border-border pt-4">
            <h2 className="text-sm font-medium text-muted-foreground mb-2">About this recording</h2>
            <p className="text-sm">
              {recording.description || "No description provided."}
            </p>
            <div className="mt-4 text-xs text-muted-foreground">
              {new Date(recording.created_at).toLocaleDateString("en-US", {
                weekday: "long",
                year: "numeric",
                month: "long",
                day: "numeric",
              })}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
