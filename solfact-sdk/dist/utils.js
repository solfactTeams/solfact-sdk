"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.systemTransferInstruction = systemTransferInstruction;
exports.derivePollPda = derivePollPda;
exports.deriveEscrowPda = deriveEscrowPda;
exports.deriveVotePda = deriveVotePda;
const web3_js_1 = require("@solana/web3.js");
function systemTransferInstruction(from, to, lamports) {
    return web3_js_1.SystemProgram.transfer({
        fromPubkey: from,
        toPubkey: to,
        lamports,
    });
}
async function derivePollPda(programId, news_hash) {
    return await web3_js_1.PublicKey.findProgramAddress([Buffer.from("poll"), Buffer.from(news_hash)], programId);
}
async function deriveEscrowPda(programId, news_hash) {
    return await web3_js_1.PublicKey.findProgramAddress([Buffer.from("escrow"), Buffer.from(news_hash)], programId);
}
async function deriveVotePda(programId, poll, voter) {
    return await web3_js_1.PublicKey.findProgramAddress([Buffer.from("vote"), poll.toBuffer(), voter.toBuffer()], programId);
}
