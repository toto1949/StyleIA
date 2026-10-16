// Supabase's managed PostgreSQL pooler uses a private CA chain.
// Preserve full server/hostname verification by installing its published
// public 2021 root CA instead of disabling TLS certificate verification.
import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const backendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const destination = path.join(backendRoot, "certs", "supabase", "prod-ca-2021.crt");
const url = "https://supabase-downloads.s3-ap-southeast-1.amazonaws.com/prod/ssl/prod-ca-2021.crt";
// SHA-256 of the DER certificate (CN=Supabase Root 2021 CA).
const expectedFingerprint = "807025AD50D4ED219D2C9C7D299C004F824EB00CF7F65AFEF607D07B72E6CAFA";

function validate(pem) {
  const certificate = new crypto.X509Certificate(pem);
  const fingerprint = crypto.createHash("sha256").update(certificate.raw).digest("hex").toUpperCase();
  if (fingerprint !== expectedFingerprint
      || !certificate.ca
      || !certificate.subject.includes("CN=Supabase Root 2021 CA")
      || certificate.subject !== certificate.issuer
      || !certificate.verify(certificate.publicKey)) {
    throw new Error("Untrusted Supabase root certificate: refusing database connection.");
  }
}

if (process.env.NODE_ENV !== "production") {
  console.log("Skipping production-only Supabase root CA provisioning.");
} else {
  await fs.mkdir(path.dirname(destination), { recursive: true });
  let pem;
  try {
    pem = await fs.readFile(destination);
    validate(pem);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    const response = await fetch(url, { redirect: "error", signal: AbortSignal.timeout(20000) });
    if (!response.ok) throw new Error(`Supabase CA download returned HTTP ${response.status}.`);
    pem = Buffer.from(await response.arrayBuffer());
    if (pem.length < 500 || pem.length > 32768) {
      throw new Error("Unexpected Supabase CA download size.");
    }
    validate(pem);
    const temp = `${destination}.${process.pid}.tmp`;
    try {
      await fs.writeFile(temp, pem, { flag: "wx", mode: 0o644 });
      await fs.rename(temp, destination);
    } finally {
      await fs.rm(temp, { force: true }).catch(() => {});
    }
  }
  console.log("Verified public Supabase Root 2021 CA for PostgreSQL TLS.");
}
