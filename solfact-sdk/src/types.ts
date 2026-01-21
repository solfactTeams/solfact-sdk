// Shared TypeScript types used by the SDK

import { PublicKey } from "@solana/web3.js";

export type FactChoice = "FACT" | "HOAX";

export interface FactCheckState {
  news_hash: string;
  creator: PublicKey;
  deadline: number;
  total_yes: number;
  total_no: number;
  resolved: boolean;
  winner: number; // 0 none, 1 yes, 2 no
  bump: number;
}
