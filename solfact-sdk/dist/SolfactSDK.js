"use strict";
/* Solfact SDK
   - Wraps Anchor program client calls into typed methods
   - Uses Anchor Provider/Program under the hood
   - Designed for SOL-based escrow variant
*/
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.SolfactSDK = void 0;
const anchor = __importStar(require("@coral-xyz/anchor"));
const anchor_1 = require("@coral-xyz/anchor");
const web3_js_1 = require("@solana/web3.js");
const solfact_json_1 = __importDefault(require("./idl/solfact.json"));
const utils_1 = require("./utils");
class SolfactSDK {
    constructor(connection, wallet, programId) {
        this.connection = connection;
        this.provider = new anchor_1.AnchorProvider(connection, wallet, anchor.AnchorProvider.defaultOptions());
        this.idl = solfact_json_1.default;
        const programAddressStr = this.idl?.metadata?.address || (programId ? programId.toBase58() : "");
        const pid = programId ? programId : new web3_js_1.PublicKey(programAddressStr);
        this.program = new anchor_1.Program(this.idl, pid, this.provider);
    }
    async createFactCheck(creatorKeypair, news_hash, deadlineTs, creatorChoice, createStakeLamports) {
        const [pollPda] = await (0, utils_1.derivePollPda)(this.program.programId, news_hash);
        const [escrowPda] = await (0, utils_1.deriveEscrowPda)(this.program.programId, news_hash);
        const preIx = (0, utils_1.systemTransferInstruction)(creatorKeypair.publicKey, escrowPda, createStakeLamports);
        await this.program.methods
            .createPoll(news_hash, new anchor.BN(deadlineTs), creatorChoice)
            .accounts({
            creator: creatorKeypair.publicKey,
            poll: pollPda,
            escrow: escrowPda,
            creatorStake: creatorKeypair.publicKey,
            systemProgram: web3_js_1.SystemProgram.programId,
            rent: anchor.web3.SYSVAR_RENT_PUBKEY,
        })
            .signers([creatorKeypair])
            .preInstructions([preIx])
            .rpc();
        return pollPda;
    }
    async voteFact(voterKeypair, pollPda, news_hash, stakeLamports) {
        return await this.voteInternal(voterKeypair, pollPda, news_hash, true, stakeLamports);
    }
    async voteHoax(voterKeypair, pollPda, news_hash, stakeLamports) {
        return await this.voteInternal(voterKeypair, pollPda, news_hash, false, stakeLamports);
    }
    async voteInternal(voterKeypair, pollPda, news_hash, choice, stakeLamports) {
        const [votePda] = await (0, utils_1.deriveVotePda)(this.program.programId, pollPda, voterKeypair.publicKey);
        const [escrowPda] = await (0, utils_1.deriveEscrowPda)(this.program.programId, news_hash);
        const preIx = (0, utils_1.systemTransferInstruction)(voterKeypair.publicKey, escrowPda, stakeLamports);
        await this.program.methods
            .vote(choice)
            .accounts({
            voter: voterKeypair.publicKey,
            poll: pollPda,
            voterStake: voterKeypair.publicKey,
            vote: votePda,
            escrow: escrowPda,
            systemProgram: web3_js_1.SystemProgram.programId,
            rent: anchor.web3.SYSVAR_RENT_PUBKEY,
        })
            .signers([voterKeypair])
            .preInstructions([preIx])
            .rpc();
        return votePda;
    }
    async resolveFactCheck(callerKeypair, pollPda, news_hash) {
        const [escrowPda] = await (0, utils_1.deriveEscrowPda)(this.program.programId, news_hash);
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
    async claimReward(claimerKeypair, pollPda, votePda, news_hash) {
        const [escrowPda] = await (0, utils_1.deriveEscrowPda)(this.program.programId, news_hash);
        await this.program.methods
            .claimReward()
            .accounts({
            claimer: claimerKeypair.publicKey,
            poll: pollPda,
            vote: votePda,
            escrow: escrowPda,
            systemProgram: web3_js_1.SystemProgram.programId,
        })
            .signers([claimerKeypair])
            .rpc();
    }
    async getFactCheckState(pollPda) {
        const acct = await this.program.account.poll.fetch(pollPda);
        return acct;
    }
    async pdasFromHash(news_hash) {
        const poll = (await (0, utils_1.derivePollPda)(this.program.programId, news_hash))[0];
        const escrow = (await (0, utils_1.deriveEscrowPda)(this.program.programId, news_hash))[0];
        return { poll, escrow };
    }
}
exports.SolfactSDK = SolfactSDK;
