import crypto from "node:crypto";
import { URL } from "node:url";

const clientsByJobId = new Map();

export function handleUpgrade(request, socket, head, authenticateSocket, onConnected) {
  try {
    const url = new URL(request.url, "http://localhost");
    const match = url.pathname.match(/^\/ws\/([^/]+)$/);
    if (!match) {
      socket.destroy();
      return;
    }

    const jobId = decodeURIComponent(match[1]);
    const token = url.searchParams.get("token") || "";
    const context = authenticateSocket(jobId, token);

    const key = request.headers["sec-websocket-key"];
    if (!key) {
      socket.destroy();
      return;
    }

    const accept = crypto
      .createHash("sha1")
      .update(`${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`)
      .digest("base64");

    socket.write([
      "HTTP/1.1 101 Switching Protocols",
      "Upgrade: websocket",
      "Connection: Upgrade",
      `Sec-WebSocket-Accept: ${accept}`,
      "",
      ""
    ].join("\r\n"));

    if (head?.length) {
      socket.unshift(head);
    }

    addClient(jobId, socket);
    socket.on("close", () => removeClient(jobId, socket));
    socket.on("end", () => removeClient(jobId, socket));
    socket.on("error", () => removeClient(jobId, socket));
    socket.on("data", (buffer) => handleIncomingFrame(socket, buffer));

    Promise.resolve(onConnected?.(jobId, context, socket)).catch(() => {
      socket.destroy();
    });
  } catch {
    socket.destroy();
  }
}

export function broadcastJobUpdate(jobId, payload) {
  const clients = clientsByJobId.get(jobId);
  if (!clients) {
    return;
  }

  const frame = encodeTextFrame(JSON.stringify(payload));
  for (const socket of clients) {
    if (!socket.destroyed) {
      socket.write(frame);
    }
  }
}

export function sendJobUpdate(socket, payload) {
  if (!socket.destroyed) {
    socket.write(encodeTextFrame(JSON.stringify(payload)));
  }
}

function addClient(jobId, socket) {
  const clients = clientsByJobId.get(jobId) || new Set();
  clients.add(socket);
  clientsByJobId.set(jobId, clients);
}

function removeClient(jobId, socket) {
  const clients = clientsByJobId.get(jobId);
  if (!clients) {
    return;
  }

  clients.delete(socket);
  if (clients.size === 0) {
    clientsByJobId.delete(jobId);
  }
}

function encodeTextFrame(text) {
  const payload = Buffer.from(text);
  const length = payload.length;

  if (length < 126) {
    return Buffer.concat([Buffer.from([0x81, length]), payload]);
  }

  if (length < 65_536) {
    const header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 126;
    header.writeUInt16BE(length, 2);
    return Buffer.concat([header, payload]);
  }

  const header = Buffer.alloc(10);
  header[0] = 0x81;
  header[1] = 127;
  header.writeBigUInt64BE(BigInt(length), 2);
  return Buffer.concat([header, payload]);
}

function handleIncomingFrame(socket, buffer) {
  const opcode = buffer[0] & 0x0f;
  if (opcode === 0x8) {
    socket.end(Buffer.from([0x88, 0x00]));
  } else if (opcode === 0x9) {
    socket.write(Buffer.from([0x8a, 0x00]));
  }
}
