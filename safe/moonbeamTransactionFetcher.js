import axios from 'axios';
import {ethers} from 'ethers';

const apiUrl =
    'https://gateway.multisig.moonbeam.network/v1/chains/1284/safes/0xF130e4946F862F2c6CA3d007D51C21688908e006/transactions/queued';

function prettyPrintScaledNumber(scaledNumber) {
    let num = BigInt(scaledNumber);
    const isNegative = num < 0n;
    if (isNegative) {
        num = -num;
    }
    num = num + 5000n;
    num = num / 10000n;
    const integerPart = num / 100n;
    let fractionalPart = num % 100n;
    let integerPartStr = integerPart.toString();
    let fractionalPartStr = fractionalPart.toString().padStart(2, '0');
    integerPartStr = integerPartStr.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    const result = `${isNegative ? '-' : ''}${integerPartStr}.${fractionalPartStr}`;
    return result;
}

function decodeData(hexString) {
    if (hexString.startsWith('0x')) {
        hexString = hexString.slice(2);
    }
    const methodId = hexString.slice(0, 8);
    if (methodId !== 'a9059cbb') {
        return [null, null];
    }
    const dataHex = hexString.slice(8);
    const abi = ['function transfer(address to, uint256 amount)'];
    const iface = new ethers.utils.Interface(abi);
    const dataWithMethodId = '0x' + methodId + dataHex;
    const decoded = iface.decodeFunctionData('transfer', dataWithMethodId);
    return decoded;
}

async function fetchTransactions() {
    try {
        const response = await axios.get(apiUrl);
        const transactions = response.data;

        if (transactions.results.length > 0) {
            for (let i = 0; i < transactions.results.length; i++) {
                const tx = transactions.results[i];
                if (
                    tx.type === 'TRANSACTION' &&
                    tx.transaction.txInfo.type === 'Transfer'
                ) {
                    const txInfo = tx.transaction.txInfo;
                    console.log(
                        `\n--------------------------------------------------------------------------------------`,
                    );
                    console.log(`\nTransaction ID: ${tx.transaction.id}`);
                    console.log(`Description: ${txInfo.humanDescription}`);
                    console.log(`Sender: ${txInfo.sender.value}`);
                    console.log(`Recipient: ${txInfo.recipient.value}`);
                    console.log(
                        `Token: ${txInfo.transferInfo.tokenName} (${txInfo.transferInfo.tokenSymbol})`,
                    );
                    console.log(
                        `Amount: ${prettyPrintScaledNumber(txInfo.transferInfo.value)}`,
                    );
                    console.log(`Status: ${tx.transaction.txStatus}`);
                    console.log(
                        `Confirmations Submitted: ${tx.transaction.executionInfo.confirmationsSubmitted}`,
                    );
                    console.log(
                        `Confirmations Required: ${tx.transaction.executionInfo.confirmationsRequired}`,
                    );
                    console.log(
                        `Missing Signers: ${tx.transaction.executionInfo.missingSigners.map((signer) => signer.value).join(', ')}`,
                    );
                    console.log(
                        `\n--------------------------------------------------------------------------------------\n`,
                    );
                } else if (
                    tx.type === 'TRANSACTION' &&
                    tx.transaction.txInfo.type === 'Custom'
                ) {
                    console.log(
                        `\n--------------------------------------------------------------------------------------`,
                    );
                    console.log(`\nTransaction ID: ${tx.transaction.id}`);
                    console.log(
                        `Description: ${tx.transaction.txInfo.humanDescription || 'Custom Transaction'}`,
                    );
                    console.log(`To: ${tx.transaction.txInfo.to.value}`);
                    console.log(
                        `Method: ${tx.transaction.txInfo.methodName || 'N/A'}`,
                    );
                    console.log(
                        `Value: ${prettyPrintScaledNumber(tx.transaction.txInfo.value)}`,
                    );
                    console.log(`Status: ${tx.transaction.txStatus}`);
                    console.log(
                        `Confirmations Submitted: ${tx.transaction.executionInfo.confirmationsSubmitted}`,
                    );
                    console.log(
                        `Confirmations Required: ${tx.transaction.executionInfo.confirmationsRequired}`,
                    );
                    console.log(
                        `Missing Signers: ${tx.transaction.executionInfo.missingSigners.map((signer) => signer.value).join(', ')}`,
                    );
                    console.log(
                        `\n--------------------------------------------------------------------------------------\n`,
                    );
                }
            }
        } else {
            console.log(`\nNo pending transactions found.\n`);
        }
    } catch (error) {
        console.error('Error fetching transactions:', error);
    }
}

fetchTransactions();
