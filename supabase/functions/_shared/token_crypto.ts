const encoder = new TextEncoder();

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function fromBase64Url(value: string): Uint8Array {
  const padded = value.replaceAll("-", "+").replaceAll("_", "/")
    .padEnd(Math.ceil(value.length / 4) * 4, "=");
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

async function encryptionKey(): Promise<CryptoKey> {
  const encoded = Deno.env.get("PAYMENT_TOKEN_ENCRYPTION_KEY")?.trim();
  if (!encoded) throw new Error("Missing server token encryption key.");
  const bytes = fromBase64Url(encoded);
  if (bytes.byteLength !== 32) {
    throw new Error("PAYMENT_TOKEN_ENCRYPTION_KEY must contain exactly 32 bytes.");
  }
  return crypto.subtle.importKey("raw", bytes.buffer as ArrayBuffer, "AES-GCM", false, ["encrypt"]);
}

export function randomState(): string {
  return base64Url(crypto.getRandomValues(new Uint8Array(32)));
}

export async function sha256(value: string): Promise<string> {
  return base64Url(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value))));
}

export async function encryptToken(token: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await encryptionKey(), encoder.encode(token)),
  );
  return JSON.stringify({ v: 1, alg: "A256GCM", iv: base64Url(iv), ciphertext: base64Url(ciphertext) });
}
