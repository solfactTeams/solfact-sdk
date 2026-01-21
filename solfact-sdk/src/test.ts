/* Example usage of the SolfactSDK.
   Run with: npx ts-node src/test.ts
*/

import * as anchor from "@coral-xyz/anchor";
import { Keypair, Connection, LAMPORTS_PER_SOL, PublicKey } from "@solana/web3.js";
import { SolfactSDK } from "./SolfactSDK";
import idlJson from "./idl/solfact.json";

(async () => {
  const connection = new Connection("http://127.0.0.1:8899", "confirmed");

  const payer = Keypair.generate();
  console.log("Requesting airdrop for payer...");
  await connection.requestAirdrop(payer.publicKey, 10 * LAMPORTS_PER_SOL);
  await new Promise((r) => setTimeout(r, 2000));

  const wallet = new anchor.Wallet(payer);

  const programIdStr = (idlJson as any).metadata?.address;
  if (!programIdStr || programIdStr.includes("REPLACE_PROGRAM_ID_AFTER_DEPLOYMENT")) {
    console.warn("Warning: Program ID in IDL not set. Please replace metadata.address in src/idl/solfact.json with deployed program ID.");
  }
  const programId = programIdStr ? new PublicKey(programIdStr) : undefined;

  const sdk = new SolfactSDK(connection, wallet, programId);

  const creator = Keypair.generate();
  const voter = Keypair.generate();
  console.log("Airdropping to creator & voter...");
  await connection.requestAirdrop(creator.publicKey, 5 * LAMPORTS_PER_SOL);
  await connection.requestAirdrop(voter.publicKey, 5 * LAMPORTS_PER_SOL);
  await new Promise((r) => setTimeout(r, 2000));

  const newsHash = "example-article-abc";
  const deadlineTs = Math.floor(Date.now() / 1000) + 12;

  console.log("Creating poll...");
  const poll = await sdk.createFactCheck(creator, newsHash, deadlineTs, true, 1 * LAMPORTS_PER_SOL);
  console.log("Poll PDA:", poll.toBase58());

  console.log("Voting HOAX...");
  const votePda = await sdk.voteHoax(voter, poll, newsHash, 1 * LAMPORTS_PER_SOL);
  console.log("Vote PDA:", votePda.toBase58());

  console.log("Waiting for deadline to pass...");
  await new Promise((r) => setTimeout(r, 14000));

  console.log("Resolving poll...");
  await sdk.resolveFactCheck(payer, poll, newsHash);

  console.log("Claiming reward for voter...");
  await sdk.claimReward(voter, poll, votePda, newsHash);

  console.log("Done.");
})();
