import crypto from "crypto"

const ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

export function generateShortId(length: number = 8): string {
  const bytes = crypto.randomBytes(length)
  let result = ""

  for (let i = 0; i < length; i++) {
    result += ALPHABET[bytes[i] % ALPHABET.length]
  }

  return result
}
