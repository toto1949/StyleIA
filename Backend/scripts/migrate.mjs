import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";

const { Pool } = pg;
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const migrationsDirectory = path.join(root, "migrations");
const databaseURL = process.env.DATABASE_URL;

if (!databaseURL) {
  throw new Error("DATABASE_URL is required to run database migrations.");
}

const pool = new Pool({
  connectionString: databaseURL,
  max: 2,
  idleTimeoutMillis: 10_000,
  connectionTimeoutMillis: 10_000,
  ssl: databaseURL.includes("localhost") || databaseURL.includes("127.0.0.1")
    ? false
    : { rejectUnauthorized: process.env.DATABASE_SSL_REJECT_UNAUTHORIZED !== "false" }
});

try {
  const files = (await fs.readdir(migrationsDirectory))
    .filter((name) => /^\d+_[a-z0-9_-]+\.sql$/i.test(name))
    .sort();

  await pool.query(`
    create table if not exists schema_migrations (
      version text primary key,
      checksum text not null,
      applied_at timestamptz not null default now()
    )
  `);

  for (const file of files) {
    const version = file.split("_", 1)[0];
    const sql = await fs.readFile(path.join(migrationsDirectory, file), "utf8");
    const checksum = crypto.createHash("sha256").update(sql).digest("hex");
    const existing = await pool.query(
      "select checksum from schema_migrations where version = $1",
      [version]
    );

    if (existing.rowCount > 0) {
      if (existing.rows[0].checksum !== checksum) {
        throw new Error(`Migration ${version} was modified after it was applied.`);
      }
      console.log(`skip ${file}`);
      continue;
    }

    const client = await pool.connect();
    try {
      await client.query("begin");
      await client.query("select pg_advisory_xact_lock($1)", [1_938_447_101]);
      await client.query(sql);
      await client.query(
        "insert into schema_migrations (version, checksum) values ($1, $2)",
        [version, checksum]
      );
      await client.query("commit");
      console.log(`applied ${file}`);
    } catch (error) {
      await client.query("rollback").catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }
} finally {
  await pool.end();
}
