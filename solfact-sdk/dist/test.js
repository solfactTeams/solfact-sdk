"use strict";
/* Example usage of the SolfactSDK.
   Run with: npx ts-node src/test.ts
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
const anchor = __importStar(require("@coral-xyz/anchor"));
const web3_js_1 = require("@solana/web3.js");
const SolfactSDK_1 = require("./SolfactSDK");
const solfact_json_1 = __importDefault(require("./idl/solfact.json"));
(async () => {
    const connection = new web3_js_1.Connection("http://127.0.0.1:8899", "confirmed");
    const payer = web3_js_1.Keypair.generate();
    console.log("Requesting airdrop for payer...");
    await connection.requestAirdrop(payer.publicKey, 10 * web3_js_1.LAMPORTS_PER_SOL);
    await new Promise((r) => setTimeout(r, 2000));
    const wallet = new anchor.Wallet(payer);
    const programIdStr = solfact_json_1.default.metadata?.address;
    if (!programIdStr || programIdStr.includes("REPLACE_PROGRAM_ID_AFTER_DEPLOYMENT")) {
        console.warn("Warning: Program ID in IDL not set. Please replace metadata.address in src/idl/solfact.json with deployed program ID.");
    }
    const programId = programIdStr ? new web3_js_1.PublicKey(programIdStr) : undefined;
    const sdk = new SolfactSDK_1.SolfactSDK(connection, wallet, programId);
    const creator = web3_js_1.Keypair.generate();
    const voter = web3_js_1.Keypair.generate();
    console.log("Airdropping to creator & voter...");
    await connection.requestAirdrop(creator.publicKey, 5 * web3_js_1.LAMPORTS_PER_SOL);
    await connection.requestAirdrop(voter.publicKey, 5 * web3_js_1.LAMPORTS_PER_SOL);
    await new Promise((r) => setTimeout(r, 2000));
    const newsHash = "example-article-abc";
    const deadlineTs = Math.floor(Date.now() / 1000) + 12;
    console.log("Creating poll...");
    const poll = await sdk.createFactCheck(creator, newsHash, deadlineTs, true, 1 * web3_js_1.LAMPORTS_PER_SOL);
    console.log("Poll PDA:", poll.toBase58());
    console.log("Voting HOAX...");
    const votePda = await sdk.voteHoax(voter, poll, newsHash, 1 * web3_js_1.LAMPORTS_PER_SOL);
    console.log("Vote PDA:", votePda.toBase58());
    console.log("Waiting for deadline to pass...");
    await new Promise((r) => setTimeout(r, 14000));
    console.log("Resolving poll...");
    await sdk.resolveFactCheck(payer, poll, newsHash);
    console.log("Claiming reward for voter...");
    await sdk.claimReward(voter, poll, votePda, newsHash);
    console.log("Done.");
})();
