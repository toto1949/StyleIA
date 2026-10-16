// Public Apple trust anchors for signed App Store transactions.
// Download from Apple's PKI site, pinned to fingerprints published in
// Apple's iOS 26 root store list. Never place signing keys in this folder.
import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const backendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const destination = path.join(backendRoot, "certs", "apple");
const certificates = [
  {
    file: "AppleIncRootCertificate.cer",
    url: "https://www.apple.com/appleca/AppleIncRootCertificate.cer",
    sha256: "B0B1730ECBC7FF4505142C49F1295E6EDA6BCAED7E2C68C5BE91B5A11001F024"
  },
  {
    file: "AppleRootCA-G2.cer",
    url: "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
    sha256: "C2B9B042DD57830E7D117DAC55AC8AE19407D38E41D88F3215BC3A890444A050"
  },
  {
    file: "AppleRootCA-G3.cer",
    url: "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
    sha256: "63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179"
  }
];

function validate(bytes, entry) {
  const digest = crypto.createHash("sha256").update(bytes).digest("hex").toUpperCase();
  if (digest !== entry.sha256) {
    throw new Error(`Unexpected SHA-256 for Apple's ${entry.file}; refusing to trust the certificate.`);
  }
  const certificate = new crypto.X509Certificate(bytes);
  if (!certificate.ca || !certificate.subject.includes("Apple")) {
    throw new Error(`Invalid Apple root CA certificate: ${entry.file}.`);
  }
}

async function download(entry) {
  const response = await fetch(entry.url, {
    headers: { Accept: "application/x-x509-ca-cert, application/octet-stream" },
    signal: AbortSignal.timeout(20000),
    redirect: "error"
  });
  if (!response.ok) throw new Error(`Apple PKI returned HTTP ${response.status} for ${entry.file}.`);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.byteLength === 0 || bytes.byteLength > 32768) {
    throw new Error(`Unexpected certificate size for ${entry.file}.`);
  }
  validate(bytes, entry);
  return bytes;
}

if (process.env.NODE_ENV !== "production") {
  console.log("Skipping production-only Apple root CA provisioning.");
} else {
  await fs.mkdir(destination, { recursive: true });
  for (const entry of certificates) {
    const target = path.join(destination, entry.file);
    let bytes;
    try {
      bytes = await fs.readFile(target);
      validate(bytes, entry);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
      bytes = await download(entry);
      const temp = `${target}.${process.pid}.tmp`;
      try {
        await fs.writeFile(temp, bytes, { flag: "wx", mode: 0o644 });
        await fs.rename(temp, target);
      } finally {
        await fs.rm(temp, { force: true }).catch(() => {});
      }
    }
    console.log(`Verified Apple public root certificate: ${entry.file}`);
  }
}
