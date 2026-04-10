import crypto from "crypto"

export function generateApiKey(): string {
  const prefix = "rs_"
  const randomBytes = crypto.randomBytes(32).toString("hex")
  return `${prefix}${randomBytes}`
}

export function hashApiKey(key: string): string {
  return crypto.createHash("sha256").update(key).digest("hex")
}
