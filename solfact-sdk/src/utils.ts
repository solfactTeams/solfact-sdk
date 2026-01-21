import * as anchor from "@coral-xyz/anchor";
import { Keypair, PublicKey, SystemProgram, TransactionInstruction } from "@solana/web3.js";

export function systemTransferInstruction(from: PublicKey, to: PublicKey, lamports: number): TransactionInstruction {
  return SystemProgram.transfer({
    fromPubkey: from,
    toPubkey: to,
    lamports,
  });
}

export async function derivePollPda(programId: PublicKey, news_hash: string): Promise<[PublicKey, number]> {
  return await PublicKey.findProgramAddress(
    [Buffer.from("poll"), Buffer.from(news_hash)],
    programId
  );
}

export async function deriveEscrowPda(programId: PublicKey, news_hash: string): Promise<[PublicKey, number]> {
  return await PublicKey.findProgramAddress(
    [Buffer.from("escrow"), Buffer.from(news_hash)],
    programId
  );
}

export async function deriveVotePda(programId: PublicKey, poll: PublicKey, voter: PublicKey): Promise<[PublicKey, number]> {
  return await PublicKey.findProgramAddress(
    [Buffer.from("vote"), poll.toBuffer(), voter.toBuffer()],
    programId
  );
}
