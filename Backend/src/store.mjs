import fs from "node:fs/promises";
import path from "node:path";

function initialData() {
  return {
    users: [],
    uploads: [],
    jobs: []
  };
}

export class JsonStore {
  constructor(filePath) {
    this.filePath = filePath;
    this.queue = Promise.resolve();
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

  async read() {
    try {
      const raw = await fs.readFile(this.filePath, "utf8");
      const parsed = JSON.parse(raw);
      return {
        users: Array.isArray(parsed.users) ? parsed.users : [],
        uploads: Array.isArray(parsed.uploads) ? parsed.uploads : [],
        jobs: Array.isArray(parsed.jobs) ? parsed.jobs : []
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
