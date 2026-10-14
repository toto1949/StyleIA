import fs from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";

function initialData() {
  return {
    users: [],
    uploads: [],
    jobs: [],
    usage: [],
    creditAccounts: [],
    creditGrants: [],
    creditLedger: [],
    entitlements: [],
    appStoreTransactions: [],
    appStoreNotifications: [],
    sessions: []
  };
}

export class JsonStore {
  constructor(filePath) {
    this.filePath = filePath;
    this.queue = Promise.resolve();
    this.rateLimits = new Map();
  }

  async init() {
    await fs.mkdir(path.dirname(this.filePath), { recursive: true });
    try {
      await fs.access(this.filePath);
    } catch {
      await this.write(initialData());
    }
  }

  async snapshot() {
    return this.read();
  }

  async mutate(operation) {
    const next = this.queue.then(async () => {
      const data = await this.read();
      const result = await operation(data);
      await this.write(data);
      return result;
    });

    this.queue = next.catch(() => {});
    return next;
  }

  // Local development uses one process. Production configuration requires
  // PostgreSQL, whose implementation coordinates this atomically across all
  // instances.
  async consumeRateLimit(scope, subjectHash, limit, windowMs) {
    const key = `${scope}:${subjectHash}`;
    const now = Date.now();
    let bucket = this.rateLimits.get(key);
    if (!bucket || bucket.resetAt <= now) {
      bucket = { count: 0, resetAt: now + windowMs };
      this.rateLimits.set(key, bucket);
    }
    bucket.count += 1;

    if (this.rateLimits.size > 5_000) {
      for (const [candidateKey, candidate] of this.rateLimits) {
        if (candidate.resetAt <= now) this.rateLimits.delete(candidateKey);
      }
    }

    return {
      allowed: bucket.count <= limit,
      remaining: Math.max(0, limit - bucket.count),
      resetAt: bucket.resetAt
    };
  }

  async createRefreshSession(userId, refreshTokenHash, expiresAt) {
    await this.mutate(async (data) => {
      const now = Date.now();
      data.sessions = (data.sessions || []).filter((session) =>
        new Date(session.expiresAt).getTime() > now && !session.revokedAt
      );
      data.sessions.push({
        id: crypto.randomUUID(),
        userId,
        refreshTokenHash,
        expiresAt,
        revokedAt: null,
        createdAt: new Date().toISOString(),
        lastUsedAt: new Date().toISOString()
      });
      const active = data.sessions
        .filter((session) => session.userId === userId && !session.revokedAt)
        .sort((left, right) => new Date(right.createdAt) - new Date(left.createdAt));
      const retained = new Set(active.slice(0, 10).map((session) => session.id));
      data.sessions = data.sessions.filter((session) =>
        session.userId !== userId || session.revokedAt || retained.has(session.id)
      );
    });
  }

  async rotateRefreshSession(oldHash, newHash, expiresAt) {
    return this.mutate(async (data) => {
      const session = (data.sessions || []).find((candidate) =>
        candidate.refreshTokenHash === oldHash
        && !candidate.revokedAt
        && new Date(candidate.expiresAt).getTime() > Date.now()
      );
      if (!session || !data.users.some((user) => user.id === session.userId)) return null;
      session.revokedAt = new Date().toISOString();
      session.lastUsedAt = session.revokedAt;
      data.sessions.push({
        id: crypto.randomUUID(),
        userId: session.userId,
        refreshTokenHash: newHash,
        expiresAt,
        revokedAt: null,
        createdAt: new Date().toISOString(),
        lastUsedAt: new Date().toISOString()
      });
      return session.userId;
    });
  }

  async revokeRefreshSession(refreshTokenHash) {
    await this.mutate(async (data) => {
      const session = (data.sessions || []).find((candidate) => candidate.refreshTokenHash === refreshTokenHash);
      if (session && !session.revokedAt) session.revokedAt = new Date().toISOString();
    });
  }

  async read() {
    try {
      const raw = await fs.readFile(this.filePath, "utf8");
      const parsed = JSON.parse(raw);
      return {
        users: Array.isArray(parsed.users) ? parsed.users : [],
        uploads: Array.isArray(parsed.uploads) ? parsed.uploads : [],
        jobs: Array.isArray(parsed.jobs) ? parsed.jobs : [],
        usage: Array.isArray(parsed.usage) ? parsed.usage : [],
        creditAccounts: Array.isArray(parsed.creditAccounts) ? parsed.creditAccounts : [],
        creditGrants: Array.isArray(parsed.creditGrants) ? parsed.creditGrants : [],
        creditLedger: Array.isArray(parsed.creditLedger) ? parsed.creditLedger : [],
        entitlements: Array.isArray(parsed.entitlements) ? parsed.entitlements : [],
        appStoreTransactions: Array.isArray(parsed.appStoreTransactions) ? parsed.appStoreTransactions : [],
        appStoreNotifications: Array.isArray(parsed.appStoreNotifications) ? parsed.appStoreNotifications : [],
        sessions: Array.isArray(parsed.sessions) ? parsed.sessions : []
      };
    } catch (error) {
      if (error.code === "ENOENT") {
        return initialData();
      }
      throw error;
    }
  }

  async write(data) {
    await fs.mkdir(path.dirname(this.filePath), { recursive: true });
    const temporaryPath = `${this.filePath}.${process.pid}.tmp`;
    await fs.writeFile(temporaryPath, JSON.stringify(data, null, 2));
    await fs.rename(temporaryPath, this.filePath);
  }
}
