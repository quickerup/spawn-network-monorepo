import { RegistryDO } from "./RegistryDO";

export { RegistryDO };

export default {
  async fetch(request: Request, env: { REGISTRY: DurableObjectNamespace }) {
    // Single shared registry instance — same DO id every time
    const id = env.REGISTRY.idFromName("global");
    const stub = env.REGISTRY.get(id);
    return stub.fetch(request);
  }
};
