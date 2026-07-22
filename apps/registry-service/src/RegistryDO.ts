interface NodeRecord {
  nodeId: string;
  url: string;
  status: "active" | "unhealthy" | "unknown";
  lastSeen: number;
}

export class RegistryDO {
  state: DurableObjectState;

  constructor(state: DurableObjectState, env: any) {
    this.state = state;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "POST" && url.pathname === "/register") {
      const body = await request.json<{ nodeId: string; url: string }>();
      const record: NodeRecord = {
        nodeId: body.nodeId,
        url: body.url,
        status: "active",
        lastSeen: Date.now(),
      };
      await this.state.storage.put(`node:${body.nodeId}`, record);
      return Response.json({ ok: true, record });
    }

    if (request.method === "POST" && url.pathname === "/status") {
      const body = await request.json<{ nodeId: string; status: NodeRecord["status"] }>();
      const existing = await this.state.storage.get<NodeRecord>(`node:${body.nodeId}`);
      if (!existing) return new Response("Unknown node", { status: 404 });
      const updated: NodeRecord = { ...existing, status: body.status, lastSeen: Date.now() };
      await this.state.storage.put(`node:${body.nodeId}`, updated);
      return Response.json({ ok: true, record: updated });
    }

    if (request.method === "GET" && url.pathname === "/nodes") {
      const all = await this.state.storage.list<NodeRecord>({ prefix: "node:" });
      return Response.json({ nodes: Array.from(all.values()) });
    }

    return new Response("Not found", { status: 404 });
  }
}
