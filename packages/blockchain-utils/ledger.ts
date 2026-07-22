export interface Block {
  height: number;
  prevHash: string;
  timestamp: number;
  transactions: any[];
  producer: string;
  signature: string;
}
export function validateBlock(block: Block): boolean {
  // stub
  return true;
}
