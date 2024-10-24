import SafeApiKit from '@safe-global/api-kit';
import {ethers} from 'ethers';

const chainId = BigInt(1);

const apiKit = new SafeApiKit.default({
    chainId,
});

const addresses = {
    treasuryMultisig: '0xE6d2687d6e4576560592C7E0c4e1a13672a24541',
};

const allowedMethods = new Set(['transfer', 'multiSend']);

function prettyPrintScaledNumber(scaledNumber) {
    // Convert the scaled number to a BigInt
    let num = BigInt(scaledNumber);

    // Check if the number is negative
    const isNegative = num < 0n;
    if (isNegative) {
        num = -num; // Make it positive for processing
    }

    // Round the number to two decimal places
    // Since the number is scaled by 1e6, we add 5000 to perform rounding at the 2nd decimal place
    num = num + 5000n; // 5000n corresponds to 0.005 when scaled

    // Adjust the scale from 1e6 to 1e2 (two decimal places)
    num = num / 10000n; // Now num is scaled by 1e2

    // Get integer and fractional parts
    const integerPart = num / 100n;
    let fractionalPart = num % 100n;

    // Convert to strings
    let integerPartStr = integerPart.toString();
    let fractionalPartStr = fractionalPart.toString().padStart(2, '0');

    // Format the integer part with commas
    integerPartStr = integerPartStr.replace(/\B(?=(\d{3})+(?!\d))/g, ',');

    // Combine integer and fractional parts
    const result = `${isNegative ? '-' : ''}${integerPartStr}.${fractionalPartStr}`;

    return result;
}

function decodeMultiSend(transactionsHex) {
    // Remove '0x' prefix if present and convert to a Buffer
    const transactionsBuffer = Buffer.from(
        transactionsHex[0].replace(/^0x/, ''),
        'hex',
    );
    const transactionsLength = transactionsBuffer.length;
    let offset = 0;

    const operations = [];
    const targets = [];
    const values = [];
    const payloads = [];

    while (offset < transactionsLength) {
        // Read operation (1 byte)
        const operation = transactionsBuffer.readUInt8(offset);
        offset += 1;

        // Read 'to' address (20 bytes)
        const toBuffer = transactionsBuffer.slice(offset, offset + 20);
        const toAddress = '0x' + toBuffer.toString('hex');
        offset += 20;

        // Read value (32 bytes)
        const valueBuffer = transactionsBuffer.slice(offset, offset + 32);
        const value = BigInt('0x' + valueBuffer.toString('hex'));
        offset += 32;

        // Read data length (32 bytes)
        const dataLengthBuffer = transactionsBuffer.slice(offset, offset + 32);
        const dataLength = BigInt('0x' + dataLengthBuffer.toString('hex'));
        offset += 32;

        // Convert data length to Number (ensure it's within safe integer range)
        const dataLengthNumber = Number(dataLength);
        if (dataLength > BigInt(Number.MAX_SAFE_INTEGER)) {
            throw new Error('Data length exceeds maximum safe integer limit');
        }

        // Read data (dataLengthNumber bytes)
        const dataBuffer = transactionsBuffer.slice(
            offset,
            offset + dataLengthNumber,
        );
        const data = '0x' + dataBuffer.toString('hex');
        offset += dataLengthNumber;

        // Store the parsed transaction details
        operations.push(operation);
        targets.push(toAddress);
        values.push(value);
        payloads.push(data);
    }

    return {
        operations,
        targets,
        values,
        payloads,
    };
}

function decodeData(hexString) {
    // Step 1: Remove '0x' prefix if present
    if (hexString.startsWith('0x')) {
        hexString = hexString.slice(2);
    }

    // Step 2: Extract the first 4 bytes (8 hex characters)
    const methodId = hexString.slice(0, 8);

    /// if not a transfer, return null
    if (methodId !== 'a9059cbb') {
        return [null, null];
    }

    // Step 3: Get the remaining data after the method ID
    const dataHex = hexString.slice(8);

    // Define the transfer ABI for decoding
    const abi = ['function transfer(address to, uint256 amount)'];

    // Create an Interface instance
    const iface = new ethers.utils.Interface(abi);

    // Reconstruct the data with the method ID
    const dataWithMethodId = '0x' + methodId + dataHex;

    // Decode the data
    const decoded = iface.decodeFunctionData('transfer', dataWithMethodId);

    return decoded;
}

/// if it's a multisend transaction, decode it
/// if it's a transfer transaction, decode it

async function fetchTransactions() {
    try {
        const transactions = await apiKit.getPendingTransactions(
            addresses.treasuryMultisig,
        );

        if (transactions.results.length > 0) {
            transactions.results = transactions.results.filter((tx) => {
                return (
                    tx.dataDecoded !== null &&
                    (tx.dataDecoded.method == 'transfer' ||
                        tx.dataDecoded.method == 'multiSend')
                );
            });

            for (let i = 0; i < transactions.results.length; i++) {
                const toAddress = transactions.results[i].to;

                console.log(
                    `\n--------------------------------------------------------------------------------------`,
                );
                console.log(
                    `\nTransaction Hash: ${transactions.results[i].transactionHash}\nTo ${toAddress}`,
                );
                console.log(
                    `--------------------------------------------------------------------------------------\n`,
                );

                if (
                    transactions.results[i].dataDecoded.method === 'multiSend'
                ) {
                    // Define the transfer ABI for decoding
                    const abi = [
                        'function multiSend(bytes memory transactions)',
                    ];

                    // Create an Interface instance
                    const iface = new ethers.utils.Interface(abi);

                    /// first decode the call to multisend
                    const data = iface.decodeFunctionData(
                        'multiSend',
                        transactions.results[i].data,
                    );

                    const decoded = decodeMultiSend(data);

                    for (let i = 0; i < decoded.payloads.length; i++) {
                        let [recipient, amount] = decodeData(
                            decoded.payloads[i],
                        );
                        if (recipient === null && amount === null) {
                            continue;
                        }

                        console.log(
                            `Recipient: ${recipient}\nAmount: ${prettyPrintScaledNumber(amount)}\nTarget: ${decoded.targets[i]}\n\n`,
                        );
                    }
                } else if (
                    transactions.results[i].dataDecoded.method === 'transfer'
                ) {
                    let [recipient, amount] = decodeData(
                        transactions.results[i].data,
                    );
                    console.log(
                        `Recipient: ${recipient}\nAmount: ${prettyPrintScaledNumber(amount)}\n\n`,
                    );
                } else {
                    console.log(
                        'Unknown method',
                        transactions.results[i].dataDecoded.method,
                    );
                }
            }
        } else {
            console.log(
                `\nNo pending transactions for ${addresses.treasuryMultisig}\n\n`,
            );
        }
    } catch (error) {
        console.error(error);
    }
}

fetchTransactions();
