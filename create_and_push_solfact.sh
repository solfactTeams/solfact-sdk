#!/usr/bin/env bash
set -euo pipefail

# -------------------- CONFIG --------------------
OWNER="0xAlchemistis"                 # GitHub owner (username or org)
REPO1="solfact-program"               # repo name for Anchor program
REPO2="solfact-sdk"                   # repo name for SDK
BRANCH="main"
PROGRAM_ID="SoLFACt1111111111111111111111111111111111"  # program id provided
PRIVATE_FLAG="--private"              # create repos as private
# ------------------------------------------------

echo "Starting creation of ${REPO1} and ${REPO2} under ${OWNER}..."

# Check dependencies
command -v git >/dev/null 2>&1 || { echo "git not found. Install git."; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "gh (GitHub CLI) not found. Install & authenticate (gh auth login)."; exit 1; }

# Helper: create a repo, init git, commit, push
create_and_push_repo() {
  local dir="$1"
  local repo="$2"
  echo "Setting up ${repo} in ${dir}..."

  # create folder
  mkdir -p "${dir}"
  pushd "${dir}" >/dev/null

  # init git
  git init -b "${BRANCH}"
  git add .
  git commit -m "Initial commit - ${repo}"

  # create remote repo via gh and push
  echo "Creating GitHub repository ${OWNER}/${repo} (private=${PRIVATE_FLAG})..."
  gh repo create "${OWNER}/${repo}" ${PRIVATE_FLAG} --source=. --remote=origin --push --confirm

  popd >/dev/null
  echo "Repository ${repo} created and pushed."
}

# ---------------- solfact-program files ----------------
echo "Writing files for ${REPO1}..."
rm -rf "${REPO1}"
mkdir -p "${REPO1}/programs/solfact/src"
mkdir -p "${REPO1}/tests"

cat > "${REPO1}/Anchor.toml" <<EOF
[programs.localnet]
solfact = "${PROGRAM_ID}"

[provider]
cluster = "localnet"
wallet = "~/.config/solana/id.json"

[registry]
url = "https://anchor.projectserum.com"

[workspace]
members = [
  "programs/solfact",
]
EOF

cat > "${REPO1}/Cargo.toml" <<'EOF'
[workspace]
members = ["programs/solfact"]
EOF

cat > "${REPO1}/programs/solfact/Cargo.toml" <<'EOF'
[package]
name = "solfact"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "lib"]

[dependencies]
anchor-lang = "0.27.0"
solana-program = "1.15.14"
thiserror = "1.0"
EOF

cat > "${REPO1}/programs/solfact/src/lib.rs" <<EOF
// Anchor program implementing SOL-based escrow staking poll voting FACT/HOAX
use anchor_lang::prelude::*;

declare_id!("${PROGRAM_ID}"); // program id set here

#[program]
pub mod solfact {
    use super::*;

    pub fn create_poll(
        ctx: Context<CreatePoll>,
        news_hash: String,
        deadline_ts: i64,
        creator_choice: bool,
    ) -> Result<()> {
        let poll = &mut ctx.accounts.poll;
        let escrow = &mut ctx.accounts.escrow;
        let clock = Clock::get()?;
        require!(deadline_ts > clock.unix_timestamp, SolfactError::InvalidDeadline);

        poll.news_hash = news_hash.clone();
        poll.creator = ctx.accounts.creator.key();
        poll.deadline = deadline_ts;
        poll.total_yes = 0;
        poll.total_no = 0;
        poll.resolved = false;
        poll.winner = 0;
        poll.bump = *ctx.bumps.get("poll").unwrap();

        escrow.poll = ctx.accounts.poll.key();
        escrow.bump = *ctx.bumps.get("escrow").unwrap();

        if creator_choice {
            poll.total_yes = poll.total_yes.checked_add(ctx.accounts.creator_stake.lamports()).ok_or(SolfactError::MathOverflow)?;
        } else {
            poll.total_no = poll.total_no.checked_add(ctx.accounts.creator_stake.lamports()).ok_or(SolfactError::MathOverflow)?;
        }

        Ok(())
    }

    pub fn vote(ctx: Context<Vote>, choice: bool) -> Result<()> {
        let poll = &mut ctx.accounts.poll;
        let vote = &mut ctx.accounts.vote;
        let clock = Clock::get()?;
        require!(clock.unix_timestamp < poll.deadline, SolfactError::PollClosed);
        require!(!poll.resolved, SolfactError::PollResolved);

        vote.voter = ctx.accounts.voter.key();
        vote.poll = poll.key();
        vote.choice = if choice {1} else {2};
        vote.stake = ctx.accounts.voter_stake.lamports();
        vote.claimed = false;
        vote.bump = *ctx.bumps.get("vote").unwrap();

        if choice {
            poll.total_yes = poll.total_yes.checked_add(vote.stake).ok_or(SolfactError::MathOverflow)?;
        } else {
            poll.total_no = poll.total_no.checked_add(vote.stake).ok_or(SolfactError::MathOverflow)?;
        }

        Ok(())
    }

    pub fn resolve_poll(ctx: Context<ResolvePoll>) -> Result<()> {
        let poll = &mut ctx.accounts.poll;
        let clock = Clock::get()?;
        require!(clock.unix_timestamp >= poll.deadline, SolfactError::TooEarlyToResolve);
        require!(!poll.resolved, SolfactError::PollResolved);

        if poll.total_yes > poll.total_no {
            poll.winner = 1;
        } else {
            poll.winner = 2;
        }
        poll.resolved = true;

        Ok(())
    }

    pub fn claim_reward(ctx: Context<ClaimReward>) -> Result<()> {
        let poll = &mut ctx.accounts.poll;
        let vote = &mut ctx.accounts.vote;
        let escrow = &mut ctx.accounts.escrow;

        require!(poll.resolved, SolfactError::PollNotResolved);
        require!(!vote.claimed, SolfactError::AlreadyClaimed);
        require!(vote.poll == poll.key(), SolfactError::InvalidVoteForPoll);

        let winner = poll.winner;
        require!(winner == vote.choice, SolfactError::NotOnWinningSide);

        let total_winning_stake = match winner {
            1 => poll.total_yes,
            2 => poll.total_no,
            _ => return Err(error!(SolfactError::InvalidWinner)),
        };

        let escrow_balance = ctx.accounts.escrow.to_account_info().lamports();

        require!(total_winning_stake > 0, SolfactError::NoWinningStake);
        let payout_u128 = (escrow_balance as u128)
            .checked_mul(vote.stake as u128)
            .ok_or(SolfactError::MathOverflow)?
            .checked_div(total_winning_stake as u128)
            .ok_or(SolfactError::MathOverflow)?;
        let payout = payout_u128 as u64;
        require!(payout > 0, SolfactError::ZeroPayout);

        let transfer_ix = solana_program::system_instruction::transfer(&escrow.key(), &ctx.accounts.claimer.key(), payout);

        anchor_lang::solana_program::program::invoke_signed(
            &transfer_ix,
            &[
                ctx.accounts.escrow.to_account_info(),
                ctx.accounts.claimer.to_account_info(),
                ctx.accounts.system_program.to_account_info(),
            ],
            &[&[b"escrow".as_ref(), poll.news_hash.as_bytes(), &[escrow.bump]]],
        )?;

        vote.claimed = true;

        Ok(())
    }
}

#[derive(Accounts)]
#[instruction(news_hash: String)]
pub struct CreatePoll<'info> {
    #[account(mut)]
    pub creator: Signer<'info>,

    #[account(
        init,
        payer = creator,
        space = 8 + Poll::MAX_SIZE,
        seeds = [b"poll", news_hash.as_bytes()],
        bump
    )]
    pub poll: Account<'info, Poll>,

    #[account(
        init,
        payer = creator,
        space = 8 + Escrow::MAX_SIZE,
        seeds = [b"escrow", news_hash.as_bytes()],
        bump
    )]
    pub escrow: Account<'info, Escrow>,

    pub creator_stake: UncheckedAccount<'info>,

    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
pub struct Vote<'info> {
    #[account(mut)]
    pub voter: Signer<'info>,

    #[account(mut, seeds = [b"poll", poll.news_hash.as_bytes()], bump = poll.bump)]
    pub poll: Account<'info, Poll>,

    pub voter_stake: UncheckedAccount<'info>,

    #[account(
        init,
        payer = voter,
        space = 8 + VoteAccount::MAX_SIZE,
        seeds = [b"vote", poll.key().as_ref(), voter.key().as_ref()],
        bump
    )]
    pub vote: Account<'info, VoteAccount>,

    #[account(mut, seeds = [b"escrow", poll.news_hash.as_bytes()], bump = escrow.bump)]
    pub escrow: Account<'info, Escrow>,

    pub system_program: Program<'info, System>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
pub struct ResolvePoll<'info> {
    #[account(mut)]
    pub caller: Signer<'info>,

    #[account(mut, seeds = [b"poll", poll.news_hash.as_bytes()], bump = poll.bump)]
    pub poll: Account<'info, Poll>,

    #[account(mut, seeds = [b"escrow", poll.news_hash.as_bytes()], bump = escrow.bump)]
    pub escrow: Account<'info, Escrow>,
}

#[derive(Accounts)]
pub struct ClaimReward<'info> {
    #[account(mut)]
    pub claimer: Signer<'info>,

    #[account(mut, seeds = [b"poll", poll.news_hash.as_bytes()], bump = poll.bump)]
    pub poll: Account<'info, Poll>,

    #[account(mut, seeds = [b"vote", poll.key().as_ref(), vote.voter.as_ref()], bump = vote.bump)]
    pub vote: Account<'info, VoteAccount>,

    #[account(mut, seeds = [b"escrow", poll.news_hash.as_bytes()], bump = escrow.bump)]
    pub escrow: Account<'info, Escrow>,

    pub system_program: Program<'info, System>,
}

#[account]
pub struct Poll {
    pub news_hash: String,
    pub creator: Pubkey,
    pub deadline: i64,
    pub total_yes: u64,
    pub total_no: u64,
    pub resolved: bool,
    pub winner: u8,
    pub bump: u8,
}

#[account]
pub struct Escrow {
    pub poll: Pubkey,
    pub bump: u8,
}

#[account]
pub struct VoteAccount {
    pub voter: Pubkey,
    pub poll: Pubkey,
    pub choice: u8,
    pub stake: u64,
    pub claimed: bool,
    pub bump: u8,
}

impl Poll {
    pub const MAX_SIZE: usize = 4 + 64 + 32 + 8 + 8 + 8 + 1 + 1 + 1;
}

impl Escrow {
    pub const MAX_SIZE: usize = 32 + 1;
}

impl VoteAccount {
    pub const MAX_SIZE: usize = 32 + 32 + 1 + 8 + 1 + 1;
}

#[error_code]
pub enum SolfactError {
    #[msg("Invalid deadline: must be in the future")]
    InvalidDeadline,
    #[msg("Poll is already closed or deadline passed")]
    PollClosed,
    #[msg("Poll already resolved")]
    PollResolved,
    #[msg("Too early to resolve poll")]
    TooEarlyToResolve,
    #[msg("Poll is not yet resolved")]
    PollNotResolved,
    #[msg("Vote already claimed")]
    AlreadyClaimed,
    #[msg("Vote does not belong to this poll")]
    InvalidVoteForPoll,
    #[msg("Voter is not on the winning side")]
    NotOnWinningSide,
    #[msg("No winning stake (division by zero)")]
    NoWinningStake,
    #[msg("Payout computed as zero lamports")]
    ZeroPayout,
    #[msg("Invalid winner computed")]
    InvalidWinner,
    #[msg("Math overflow")]
    MathOverflow,
}
EOF

cat > "${REPO1}/tests/solfact.ts" <<'EOF'
import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { Keypair, SystemProgram, LAMPORTS_PER_SOL } from "@solana/web3.js";
import { expect } from "chai";

describe("solfact-program (integration)", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);
  const program = anchor.workspace.Solfact as Program<any>;

  const airdrop = async (kp: Keypair, sol = 2) => {
    const sig = await provider.connection.requestAirdrop(kp.publicKey, sol * LAMPORTS_PER_SOL);
    await provider.connection.confirmTransaction(sig);
  };

  it("creates a poll, votes, resolves and claims", async () => {
    const creator = Keypair.generate();
    const voter = Keypair.generate();

    await airdrop(creator, 5);
    await airdrop(voter, 5);

    const news_hash = "news-article-123";
    const deadline = Math.floor(Date.now() / 1000) + 10;

    const [pollPda] = await anchor.web3.PublicKey.findProgramAddress(
      [Buffer.from("poll"), Buffer.from(news_hash)],
      program.programId
    );
    const [escrowPda] = await anchor.web3.PublicKey.findProgramAddress(
      [Buffer.from("escrow"), Buffer.from(news_hash)],
      program.programId
    );

    const creatorStake = 1 * LAMPORTS_PER_SOL;
    await program.methods
      .createPoll(news_hash, new anchor.BN(deadline), true)
      .accounts({
        creator: creator.publicKey,
        poll: pollPda,
        escrow: escrowPda,
        creatorStake: creator.publicKey,
        systemProgram: SystemProgram.programId,
        rent: anchor.web3.SYSVAR_RENT_PUBKEY,
      })
      .signers([creator])
      .preInstructions([
        SystemProgram.transfer({
          fromPubkey: creator.publicKey,
          toPubkey: escrowPda,
          lamports: creatorStake,
        }),
      ])
      .rpc();

    const pollAccount = await program.account.poll.fetch(pollPda);
    expect(pollAccount.creator.toBase58()).to.equal(creator.publicKey.toBase58());

    const voterStake = 1 * LAMPORTS_PER_SOL;
    const [votePda] = await anchor.web3.PublicKey.findProgramAddress(
      [Buffer.from("vote"), pollPda.toBuffer(), voter.publicKey.toBuffer()],
      program.programId
    );

    await program.methods
      .vote(false)
      .accounts({
        voter: voter.publicKey,
        poll: pollPda,
        voterStake: voter.publicKey,
        vote: votePda,
        escrow: escrowPda,
        systemProgram: SystemProgram.programId,
        rent: anchor.web3.SYSVAR_RENT_PUBKEY,
      })
      .signers([voter])
      .preInstructions([
        SystemProgram.transfer({
          fromPubkey: voter.publicKey,
          toPubkey: escrowPda,
          lamports: voterStake,
        }),
      ])
      .rpc();

    await new Promise((res) => setTimeout(res, 12000));

    await program.methods
      .resolvePoll()
      .accounts({
        caller: provider.wallet.publicKey,
        poll: pollPda,
        escrow: escrowPda,
      })
      .rpc();

    const pollAfter = await program.account.poll.fetch(pollPda);
    expect(pollAfter.resolved).to.be.true;
    expect(pollAfter.winner.toNumber()).to.equal(2);

    await program.methods
      .claimReward()
      .accounts({
        claimer: voter.publicKey,
        poll: pollPda,
        vote: votePda,
        escrow: escrowPda,
        systemProgram: SystemProgram.programId,
      })
      .signers([voter])
      .rpc();

    const voteAccount = await program.account.voteAccount.fetch(votePda);
    expect(voteAccount.claimed).to.be.true;
  });
});
EOF

# ---------------- solfact-sdk files ----------------
echo "Writing files for ${REPO2}..."
rm -rf "${REPO2}"
mkdir -p "${REPO2}/src/idl"
mkdir -p "${REPO2}/src"

cat > "${REPO2}/package.json" <<'EOF'
{
  "name": "solfact-sdk",
  "version": "0.1.0",
  "description": "TypeScript SDK for Solfact Anchor program (SOL staking FACT/HOAX voting)",
  "main": "dist/index.js",
  "scripts": {
    "build": "tsc",
    "start": "ts-node src/test.ts",
    "test": "ts-node src/test.ts"
  },
  "keywords": [],
  "author": "",
  "license": "MIT",
  "dependencies": {
    "@coral-xyz/anchor": "^0.27.0",
    "@solana/web3.js": "^1.93.0",
    "bn.js": "^5.2.1"
  },
  "devDependencies": {
    "ts-node": "^10.9.1",
    "typescript": "^5.1.3"
  }
}
EOF

cat > "${REPO2}/tsconfig.json" <<'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "CommonJS",
    "strict": true,
    "esModuleInterop": true,
    "outDir": "dist",
    "rootDir": "src",
    "resolveJsonModule": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*"]
}
EOF

cat > "${REPO2}/src/idl/solfact.json" <<EOF
{
  "version": "0.1.0",
  "name": "solfact",
  "instructions": [
    {
      "name": "createPoll",
      "accounts": [
        { "name": "creator", "isMut": true, "isSigner": true },
        { "name": "poll", "isMut": true, "isSigner": false },
        { "name": "escrow", "isMut": true, "isSigner": false },
        { "name": "creatorStake", "isMut": false, "isSigner": false },
        { "name": "systemProgram", "isMut": false, "isSigner": false },
        { "name": "rent", "isMut": false, "isSigner": false }
      ],
      "args": [
        { "name": "newsHash", "type": "string" },
        { "name": "deadlineTs", "type": "i64" },
        { "name": "creatorChoice", "type": "bool" }
      ]
    },
    {
      "name": "vote",
      "accounts": [
        { "name": "voter", "isMut": true, "isSigner": true },
        { "name": "poll", "isMut": true, "isSigner": false },
        { "name": "voterStake", "isMut": false, "isSigner": false },
        { "name": "vote", "isMut": true, "isSigner": false },
        { "name": "escrow", "isMut": true, "isSigner": false },
        { "name": "systemProgram", "isMut": false, "isSigner": false },
        { "name": "rent", "isMut": false, "isSigner": false }
      ],
      "args": [
        { "name": "choice", "type": "bool" }
      ]
    },
    {
      "name": "resolvePoll",
      "accounts": [
        { "name": "caller", "isMut": true, "isSigner": true },
        { "name": "poll", "isMut": true, "isSigner": false },
        { "name": "escrow", "isMut": true, "isSigner": false }
      ],
      "args": []
    },
    {
      "name": "claimReward",
      "accounts": [
        { "name": "claimer", "isMut": true, "isSigner": true },
        { "name": "poll", "isMut": true, "isSigner": false },
        { "name": "vote", "isMut": true, "isSigner": false },
        { "name": "escrow", "isMut": true, "isSigner": false },
        { "name": "systemProgram", "isMut": false, "isSigner": false }
      ],
      "args": []
    }
  ],
  "accounts": [
    {
      "name": "poll",
      "type": {
        "kind": "struct",
        "fields": [
          { "name": "news_hash", "type": "string" },
          { "name": "creator", "type": "publicKey" },
          { "name": "deadline", "type": "i64" },
          { "name": "total_yes", "type": "u64" },
          { "name": "total_no", "type": "u64" },
          { "name": "resolved", "type": "bool" },
          { "name": "winner", "type": "u8" },
          { "name": "bump", "type": "u8" }
        ]
      }
    },
    {
      "name": "escrow",
      "type": {
        "kind": "struct",
        "fields": [
          { "name": "poll", "type": "publicKey" },
          { "name": "bump", "type": "u8" }
        ]
      }
    },
    {
      "name": "voteAccount",
      "type": {
        "kind": "struct",
        "fields": [
          { "name": "voter", "type": "publicKey" },
          { "name": "poll", "type": "publicKey" },
          { "name": "choice", "type": "u8" },
          { "name": "stake", "type": "u64" },
          { "name": "claimed", "type": "bool" },
          { "name": "bump", "type": "u8" }
        ]
      }
    }
  ],
  "metadata": {
    "address": "${PROGRAM_ID}"
  }
}
EOF

cat > "${REPO2}/src/types.ts" <<'EOF'
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
EOF

cat > "${REPO2}/src/utils.ts" <<'EOF'
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
EOF

cat > "${REPO2}/src/SolfactSDK.ts" <<'EOF'
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
EOF

cat > "${REPO2}/src/test.ts" <<'EOF'
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
EOF

# ---------------- Commit & push repos ----------------
echo "Creating and pushing ${REPO1}..."
create_and_push_repo "${REPO1}" "${REPO1}"

echo "Creating and pushing ${REPO2}..."
create_and_push_repo "${REPO2}" "${REPO2}"

echo "All done!"
echo "Notes:"
echo "- Repos created under ${OWNER}. Visit https://github.com/${OWNER}/${REPO1} and https://github.com/${OWNER}/${REPO2}"
echo "- To build/deploy Anchor program locally: cd ${REPO1} && anchor build && anchor deploy"
echo "- After deploy, ensure Anchor.toml, declare_id! in lib.rs and src/idl/solfact.json have the final deployed program id if changed."