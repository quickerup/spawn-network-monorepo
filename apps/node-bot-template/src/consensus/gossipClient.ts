import { broadcast } from "@spawn/consensus-protocol";

export async function gossipTransaction(tx: unknown, env: any) {
  // TODO: fan out to known peer node DOs via env-configured peer list
  return broadcast(tx);
}
