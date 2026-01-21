/* Solfact SDK
   - Wraps Anchor program client calls into typed methods
   - Uses Anchor Provider/Program under the hood
   - Designed for SOL-based escrow variant
*/

import * as anchor from "@coral-xyz/anchor";
import { Program, AnchorProvider, Idl } from "@coral-xyz/anchor";
import { Keypair, PublicKey, Connection, SystemProgram } from "@solana/web3.js";
import idlJson from "./idl/solfact.json";
import { derivePollPda, deriveEscrowPda, deriveVotePda, systemTransferInstruction } from "./utils";

export class SolfactSDK {
  connection: Connection;
  provider: AnchorProvider;
  program: Program;
  idl: Idl;

  constructor(connection: Connection, wallet: anchor.Wallet, programId?: PublicKey) {
    this.connection = connection;
    this.provider = new AnchorProvider(connection, wallet, anchor.AnchorProvider.defaultOptions());
    this.idl = idlJson as Idl;

    const programAddressStr: string = (this.idl as any)?.metadata?.address || (programId ? programId.toBase58() : "");
    const pid = programId ? programId : new PublicKey(programAddressStr);
    this.program = new Program(this.idl, pid, this.provider);
  }

  async createFactCheck(
    creatorKeypair: Keypair,
    news_hash: string,
    deadlineTs: number,
    creatorChoice: boolean,
    createStakeLamports: number
  ): Promise<PublicKey> {
    const [pollPda] = await derivePollPda(this.program.programId, news_hash);
    const [escrowPda] = await deriveEscrowPda(this.program.programId, news_hash);

    const preIx = systemTransferInstruction(creatorKeypair.publicKey, escrowPda, createStakeLamports);

    await this.program.methods
      .createPoll(news_hash, new anchor.BN(deadlineTs), creatorChoice)
      .accounts({
        creator: creatorKeypair.publicKey,
        poll: pollPda,
        escrow: escrowPda,
        creatorStake: creatorKeypair.publicKey,
        systemProgram: SystemProgram.programId,
        rent: anchor.web3.SYSVAR_RENT_PUBKEY,
      })
      .signers([creatorKeypair])
      .preInstructions([preIx])
      .rpc();

    return pollPda;
  }

  async voteFact(voterKeypair: Keypair, pollPda: PublicKey, news_hash: string, stakeLamports: number): Promise<PublicKey> {
    return await this.voteInternal(voterKeypair, pollPda, news_hash, true, stakeLamports);
  }

  async voteHoax(voterKeypair: Keypair, pollPda: PublicKey, news_hash: string, stakeLamports: number): Promise<PublicKey> {
    return await this.voteInternal(voterKeypair, pollPda, news_hash, false, stakeLamports);
  }

  private async voteInternal(voterKeypair: Keypair, pollPda: PublicKey, news_hash: string, choice: boolean, stakeLamports: number): Promise<PublicKey> {
    const [votePda] = await deriveVotePda(this.program.programId, pollPda, voterKeypair.publicKey);
    const [escrowPda] = await deriveEscrowPda(this.program.programId, news_hash);

    const preIx = systemTransferInstruction(voterKeypair.publicKey, escrowPda, stakeLamports);

    await this.program.methods
      .vote(choice)
      .accounts({
        voter: voterKeypair.publicKey,
        poll: pollPda,
        voterStake: voterKeypair.publicKey,
        vote: votePda,
        escrow: escrowPda,
        systemProgram: SystemProgram.programId,
        rent: anchor.web3.SYSVAR_RENT_PUBKEY,
      })
      .signers([voterKeypair])
      .preInstructions([preIx])
      .rpc();

    return votePda;
  }

  async resolveFactCheck(callerKeypair: Keypair, pollPda: PublicKey, news_hash: string): Promise<void> {
    const [escrowPda] = await deriveEscrowPda(this.program.programId, news_hash);
    await this.program.methods
      .resolvePoll()
      .accounts({
        caller: callerKeypair.publicKey,
        poll: pollPda,
        escrow: escrowPda,
      })
      .signers([callerKeypair])
      .rpc();
  }

  async claimReward(claimerKeypair: Keypair, pollPda: PublicKey, votePda: PublicKey, news_hash: string): Promise<void> {
    const [escrowPda] = await deriveEscrowPda(this.program.programId, news_hash);
    await this.program.methods
      .claimReward()
      .accounts({
        claimer: claimerKeypair.publicKey,
        poll: pollPda,
        vote: votePda,
        escrow: escrowPda,
        systemProgram: SystemProgram.programId,
      })
      .signers([claimerKeypair])
      .rpc();
  }

  async getFactCheckState(pollPda: PublicKey) {
    const acct = await this.program.account.poll.fetch(pollPda);
    return acct as any;
  }

  async pdasFromHash(news_hash: string) {
    const poll = (await derivePollPda(this.program.programId, news_hash))[0];
    const escrow = (await deriveEscrowPda(this.program.programId, news_hash))[0];
    return { poll, escrow };
  }
}
