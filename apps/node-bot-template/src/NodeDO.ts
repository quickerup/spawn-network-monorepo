export class NodeDO {
  constructor(state: DurableObjectState, env: any) {}
  async fetch(request: Request) {
    return new Response("Node DO placeholder");
  }
}
