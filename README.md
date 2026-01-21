# Solfact: SOL-Based Escrow Staking Poll Voting System

A decentralized fact-checking protocol on Solana where users stake SOL to vote on news credibility (FACT vs HOAX). Built with Anchor and TypeScript, featuring an escrow-based reward distribution mechanism.

## 📋 Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Usage](#usage)
- [API Reference](#api-reference)
- [Development](#development)
- [Testing](#testing)
- [Deployment](#deployment)

## 🎯 Overview

Solfact is a decentralized fact-checking system that leverages blockchain technology and economic incentives to establish truth. Users stake SOL tokens to vote whether news is FACT or HOAX. Winners receive rewards from the escrow pool proportional to their stake.

### Key Features
- **SOL-Based Staking**: Economic skin-in-the-game mechanism
- **Escrow Pool**: Losers' stakes fund winner rewards
- **Proof-of-Stake Voting**: Vote weight proportional to stake amount
- **On-Chain Resolution**: Transparent, verifiable outcomes
- **Reward Distribution**: Automatic proportional payout to winners

### How It Works

```
1. Creator creates a poll with a deadline and stakes SOL (votes FACT or HOAX)
2. Voters stake SOL to vote on the poll outcome
3. After deadline, poll is resolved - majority wins
4. Winners claim rewards from escrow (losers' stakes)
5. Payout = (escrow_balance × voter_stake) / total_winning_stake
```

## 🏗️ Architecture

### System Components

```
┌─────────────────────────────────────────────────────┐
│                   Solana Network                     │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │      Solfact Anchor Program                  │   │
│  │  (Program ID: SoLFACt1111...)                │   │
│  │                                              │   │
│  │  Instructions:                               │   │
│  │  • create_poll      → Initialize poll        │   │
│  │  • vote             → Cast vote + stake      │   │
│  │  • resolve_poll     → Determine winner       │   │
│  │  • claim_reward     → Distribute rewards     │   │
│  │                                              │   │
│  │  Accounts:                                   │   │
│  │  • Poll PDA         → Poll state            │   │
│  │  • Escrow PDA       → Reward pool           │   │
│  │  • VoteAccount PDA  → Vote records          │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
└─────────────────────────────────────────────────────┘
         ↑                                  ↑
         └──────────────────┬──────────────┘
                            │
                    TypeScript/Node.js
                    ┌──────────────────┐
                    │ SolfactSDK        │
                    │ Client Library    │
                    └──────────────────┘
                            ↑
                    ┌──────────────────┐
                    │ Frontend Apps    │
                    │ Scripts          │
                    │ Bot Services     │
                    └──────────────────┘
```

### Data Structures

#### Poll Account
```rust
pub struct Poll {
    pub news_hash: String,      // Unique identifier for the news
    pub creator: Pubkey,        // Poll creator address
    pub deadline: i64,          // Unix timestamp deadline
    pub total_yes: u64,         // Total lamports staked on FACT
    pub total_no: u64,          // Total lamports staked on HOAX
    pub resolved: bool,         // Whether poll is resolved
    pub winner: u8,             // 0=none, 1=FACT, 2=HOAX
    pub bump: u8,               // PDA bump seed
}
```

#### VoteAccount
```rust
pub struct VoteAccount {
    pub voter: Pubkey,          // Voter address
    pub poll: Pubkey,           // Associated poll
    pub choice: u8,             // 1=FACT, 2=HOAX
    pub stake: u64,             // Lamports staked
    pub claimed: bool,          // Reward claimed status
    pub bump: u8,               // PDA bump seed
}
```

#### Escrow Account
```rust
pub struct Escrow {
    pub poll: Pubkey,           // Associated poll
    pub bump: u8,               // PDA bump seed
}
```

## 📁 Project Structure

```
solfact/
├── solfact-program/              # Anchor smart contract
│   ├── Anchor.toml              # Anchor configuration
│   ├── Cargo.toml               # Workspace manifest
│   ├── programs/solfact/        # Program crate
│   │   ├── Cargo.toml           # Program dependencies
│   │   └── src/
│   │       └── lib.rs           # Program implementation
│   └── tests/
│       └── solfact.ts           # Integration tests
│
└── solfact-sdk/                 # TypeScript client SDK
    ├── package.json             # Dependencies & scripts
    ├── tsconfig.json            # TypeScript config
    ├── src/
    │   ├── SolfactSDK.ts         # Main SDK class
    │   ├── types.ts              # Type definitions
    │   ├── utils.ts              # PDA derivation & helpers
    │   ├── test.ts               # Example usage
    │   └── idl/
    │       └── solfact.json      # Program IDL
    └── dist/                     # Compiled output
```

## 🚀 Quick Start

### Prerequisites
- Node.js v18+ and npm
- Rust and Anchor CLI (for program development)
- Solana CLI (for deployment)
- Git

### Setup in 3 Steps

```bash
# 1. Clone the repository
git clone https://github.com/0xAlchemistis/solfact.git
cd solfact

# 2. Setup SDK
cd solfact-sdk
npm install
npm run build

# 3. Deploy program (requires Solana setup)
cd ../solfact-program
anchor build
anchor deploy
```

## 📦 Installation

### SDK Installation

```bash
cd solfact-sdk
npm install
```

### Program Setup

```bash
cd solfact-program

# Install dependencies
cargo fetch

# Build the program
anchor build

# Run tests (requires local Solana validator)
anchor test
```

## 💻 Usage

### Using the SDK

#### Basic Setup

```typescript
import * as anchor from "@coral-xyz/anchor";
import { Keypair, Connection, LAMPORTS_PER_SOL } from "@solana/web3.js";
import { SolfactSDK } from "./SolfactSDK";

// Initialize connection
const connection = new Connection("http://127.0.0.1:8899", "confirmed");
const wallet = new anchor.Wallet(Keypair.generate());

// Initialize SDK
const sdk = new SolfactSDK(connection, wallet);
```

#### Create a Poll

```typescript
// Create a fact-check poll
const newsHash = "article-uuid-123";
const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
const creatorChoice = true; // Creator votes FACT
const stakeAmount = 1 * LAMPORTS_PER_SOL; // 1 SOL

const pollPda = await sdk.createFactCheck(
  creatorKeypair,
  newsHash,
  deadline,
  creatorChoice,
  stakeAmount
);

console.log("Poll created:", pollPda.toBase58());
```

#### Vote on a Poll

```typescript
// Vote FACT
const votePda = await sdk.voteFact(
  voterKeypair,
  pollPda,
  newsHash,
  0.5 * LAMPORTS_PER_SOL
);

// Vote HOAX
const votePda = await sdk.voteHoax(
  voterKeypair,
  pollPda,
  newsHash,
  0.5 * LAMPORTS_PER_SOL
);
```

#### Resolve and Claim

```typescript
// Wait for deadline to pass, then resolve
await sdk.resolveFactCheck(
  resolverKeypair,
  pollPda,
  newsHash
);

// Claim reward (if on winning side)
await sdk.claimReward(
  voterKeypair,
  pollPda,
  votePda,
  newsHash
);
```

#### Query Poll State

```typescript
const pollState = await sdk.getFactCheckState(pollPda);
console.log("Poll winner:", pollState.winner); // 1=FACT, 2=HOAX
console.log("Total FACT votes:", pollState.total_yes);
console.log("Total HOAX votes:", pollState.total_no);
```

### Using the Program Directly

#### Create Poll Instruction

```typescript
await program.methods
  .createPoll(newsHash, new anchor.BN(deadline), true)
  .accounts({
    creator: creatorKeypair.publicKey,
    poll: pollPda,
    escrow: escrowPda,
    creatorStake: creatorKeypair.publicKey,
    systemProgram: SystemProgram.programId,
    rent: anchor.web3.SYSVAR_RENT_PUBKEY,
  })
  .signers([creatorKeypair])
  .preInstructions([transferIx])
  .rpc();
```

## 📚 API Reference

### SolfactSDK Class

#### Methods

##### `createFactCheck()`
Creates a new fact-check poll with creator's stake.

```typescript
async createFactCheck(
  creatorKeypair: Keypair,
  news_hash: string,
  deadlineTs: number,
  creatorChoice: boolean,
  createStakeLamports: number
): Promise<PublicKey>
```

**Parameters:**
- `creatorKeypair`: Creator's keypair for signing
- `news_hash`: Unique identifier for the news
- `deadlineTs`: Unix timestamp for voting deadline
- `creatorChoice`: Creator's vote (true=FACT, false=HOAX)
- `createStakeLamports`: Amount to stake in lamports

**Returns:** Poll PDA public key

---

##### `voteFact()`
Vote that news is FACT with staked SOL.

```typescript
async voteFact(
  voterKeypair: Keypair,
  pollPda: PublicKey,
  news_hash: string,
  stakeLamports: number
): Promise<PublicKey>
```

**Returns:** Vote account PDA

---

##### `voteHoax()`
Vote that news is HOAX with staked SOL.

```typescript
async voteHoax(
  voterKeypair: Keypair,
  pollPda: PublicKey,
  news_hash: string,
  stakeLamports: number
): Promise<PublicKey>
```

**Returns:** Vote account PDA

---

##### `resolveFactCheck()`
Resolve the poll after deadline - determines winner.

```typescript
async resolveFactCheck(
  callerKeypair: Keypair,
  pollPda: PublicKey,
  news_hash: string
): Promise<void>
```

---

##### `claimReward()`
Claim reward from escrow (only for winners).

```typescript
async claimReward(
  claimerKeypair: Keypair,
  pollPda: PublicKey,
  votePda: PublicKey,
  news_hash: string
): Promise<void>
```

---

##### `getFactCheckState()`
Fetch the current state of a poll.

```typescript
async getFactCheckState(pollPda: PublicKey): Promise<FactCheckState>
```

**Returns:** Poll state object

---

##### `pdasFromHash()`
Derive PDAs for a news hash without on-chain queries.

```typescript
async pdasFromHash(news_hash: string): Promise<{
  poll: PublicKey;
  escrow: PublicKey;
}>
```

---

### Utility Functions

#### `derivePollPda()`
```typescript
async derivePollPda(
  programId: PublicKey,
  news_hash: string
): Promise<[PublicKey, number]>
```

#### `deriveEscrowPda()`
```typescript
async deriveEscrowPda(
  programId: PublicKey,
  news_hash: string
): Promise<[PublicKey, number]>
```

#### `deriveVotePda()`
```typescript
async deriveVotePda(
  programId: PublicKey,
  poll: PublicKey,
  voter: PublicKey
): Promise<[PublicKey, number]>
```

#### `systemTransferInstruction()`
```typescript
function systemTransferInstruction(
  from: PublicKey,
  to: PublicKey,
  lamports: number
): TransactionInstruction
```

## 🛠️ Development

### Building the Program

```bash
cd solfact-program
anchor build
```

This generates:
- `target/deploy/solfact.so` - Compiled program
- `target/idl/solfact.json` - Program IDL

### Building the SDK

```bash
cd solfact-sdk
npm run build
```

Output in `dist/` directory

### Code Organization

**Program** (`solfact-program/programs/solfact/src/lib.rs`):
- `#[program]` module: Instruction handlers
- `#[derive(Accounts)]` structs: Account validation
- Data structures: Poll, Escrow, VoteAccount
- Error types: Custom error codes

**SDK** (`solfact-sdk/src/`):
- `SolfactSDK.ts`: Main client class
- `types.ts`: TypeScript interfaces
- `utils.ts`: Helper functions
- `test.ts`: Example usage

## 🧪 Testing

### Run SDK Tests

```bash
cd solfact-sdk
npm run build  # Build first
npm test       # Run tests
```

### Run Program Tests

```bash
cd solfact-program

# Start local Solana validator
solana-test-validator

# In another terminal
anchor test
```

### Test Coverage

The integration test (`tests/solfact.ts`) covers:
- ✅ Poll creation with creator stake
- ✅ Voting from multiple accounts
- ✅ Poll resolution after deadline
- ✅ Reward claiming for winners
- ✅ Stake accumulation and distribution

## 🚢 Deployment

### Local Testing

```bash
# Terminal 1: Start validator
solana-test-validator

# Terminal 2: Build and deploy
cd solfact-program
anchor deploy

# Get deployed program ID from output
# Update: Anchor.toml, declare_id! in lib.rs, and src/idl/solfact.json
```

### Devnet Deployment

```bash
# Configure for devnet
solana config set --url https://api.devnet.solana.com

# Deploy
cd solfact-program
anchor deploy --provider.cluster devnet
```

### Mainnet Deployment

```bash
# ⚠️ Requires audited code and careful configuration
solana config set --url https://api.mainnet-beta.solana.com
anchor deploy --provider.cluster mainnet-beta
```

### Post-Deployment

After deployment, update all references to the program ID:

1. **Anchor.toml**
   ```toml
   [programs.mainnet-beta]
   solfact = "YOUR_DEPLOYED_PROGRAM_ID"
   ```

2. **lib.rs**
   ```rust
   declare_id!("YOUR_DEPLOYED_PROGRAM_ID");
   ```

3. **solfact.json**
   ```json
   {
     "metadata": {
       "address": "YOUR_DEPLOYED_PROGRAM_ID"
     }
   }
   ```

## 🔒 Security Considerations

### Current Implementation
- ✅ Anchor built-in account validation
- ✅ PDA-based account derivation
- ✅ Checked arithmetic (overflow protection)
- ✅ Deadline enforcement
- ✅ Winner validation before payout

### Recommendations for Production
1. **Audit**: Get smart contract audited by professional auditors
2. **Bump Seeds**: Verify bump seed calculations
3. **Reentrancy**: Add guards against reentrancy attacks
4. **Limits**: Implement caps on poll count per creator
5. **Rate Limiting**: Throttle claim rewards instructions
6. **Governance**: Add multi-sig authority for upgrades

## 📊 Constants & Limits

```rust
// Program space allocations
Poll::MAX_SIZE:      140 bytes
Escrow::MAX_SIZE:    33 bytes
VoteAccount::MAX_SIZE: 74 bytes

// String limits
news_hash: String    // 4 + len bytes

// Numerical limits
u64 max stake:       18,446,744,073,709,551,615 lamports
i64 deadline:        UTC timestamps
```

## 🐛 Troubleshooting

### "Resource not accessible by integration" on GitHub deployment
- Solution: Create repos manually or use personal GitHub token with `repo` scope

### "Program not found" when claiming rewards
- Ensure program is deployed to network specified in connection URL
- Verify program ID in IDL matches deployed program

### "Insufficient funds" errors
- Request SOL airdrop on devnet: `solana airdrop 2`
- Use faucet or fund account for mainnet

### "Deadline not met" when voting
- Check server time vs poll deadline
- Ensure unix timestamps in seconds (not milliseconds)

## 📄 License

MIT License - See LICENSE file

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit pull request

## 📞 Support

For issues and questions:
- GitHub Issues: [Create an issue](https://github.com/0xAlchemistis/solfact/issues)
- Discussions: [Start a discussion](https://github.com/0xAlchemistis/solfact/discussions)

---

**Built with ❤️ for the Solana ecosystem**