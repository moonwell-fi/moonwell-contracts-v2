const {ethers} = require('ethers');
const {Defender} = require('@openzeppelin/defender-sdk');
const {KeyValueStoreClient} = require('defender-kvstore-client');
const axios = require('axios');

const temporalGovernorABI = [
    'function queueProposal(bytes VAA)',
    'function executeProposal(bytes VAA)',
];

// Use Moonbeam for Base
// const network = 'moonbeam';
// Use Moonbase Alpha for Base Sepolia
const network = 'moonbase';

const tgAddress =
    network === 'moonbase'
        ? '0x5713dd9a2b2ce515cf9232f48b457aebfb04b292' // TemporalGovernor on Base Sepolia
        : '0x8b621804a7637b781e2BbD58e256a591F2dF7d51'; // TemporalGovernor on Base

// Block explorer URL
const blockExplorer =
    network === 'moonbase'
        ? 'https://sepolia.basescan.org/tx/'
        : 'https://basescan.org/tx/';

class MoonwellEvent {
    async sendDiscordMessage(url, payload) {
        console.log('Sending Discord message...');
        if (!url) {
            throw new Error('Discord webhook url is invalid!');
        }
        console.log('SENDING', JSON.stringify(payload, null, 2));
        try {
            const response = await axios.post(url, payload, {
                headers: {
                    Accept: 'application/json',
                    'Content-Type': 'application/json',
                },
            });
            console.log(`Status code: ${response.status}`);
            console.log(
                `Response data: ${JSON.stringify(response.data, null, 2)}`,
            );
        } catch (error) {
            console.error(`Error message: ${error.message}`);
        }
        console.log('Sent Discord message!');
    }

    discordMessagePayload(
        color,
        resultText,
        txURL,
        networkName,
        sequence,
        timestamp,
    ) {
        const friendlyNetworkName =
            networkName === 'moonbase' ? 'Base Sepolia' : 'Base';
        const mipNumber = sequence - 1;
        let mipString = '';
        if (mipNumber < 10) {
            mipString = `MIP-B0${mipNumber}`;
        } else {
            mipString = `MIP-B${mipNumber}`;
        }
        const text = `${resultText.slice(0, 1).toUpperCase()}${resultText.slice(1)} ${mipString} on ${friendlyNetworkName}`;
        const details = `Governance proposal ${mipString} ${resultText} on the ${friendlyNetworkName} network.`;
        const baseFields = [
            {
                name: 'Network',
                value: friendlyNetworkName,
                inline: true,
            },
            {
                name: 'Proposal',
                value: mipString,
                inline: true,
            },
        ];

        if (timestamp && timestamp > 0) {
            baseFields.push({
                name: 'Executed at',
                value: `<t:${timestamp}>`,
                inline: true,
            });
        }

        if (details) {
            baseFields.push({
                name: 'Details',
                value: details,
                inline: false,
            });
        }

        return {
            content: '',
            embeds: [
                {
                    title: `${text}`,
                    color: color,
                    fields: baseFields,
                    url: txURL,
                },
            ],
        };
    }

    discordFormatLink(text, url) {
        return `[${text}](${url})`;
    }

    numberWithCommas(num) {
        if (!num.includes('.')) {
            num = num + '.0';
        }
        const parts = num.toString().split('.');
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        return parts
            .join('.')
            .replace(/(\.\d+[1-9])0+$/, '$1')
            .replace(/\.0+$/, '');
    }
}

const fetchVAA = async (sequence, retries = 5, delay = 2000) => {
    const apiEndpoint = `https://vaa-fetch.moonwell.workers.dev/?network=${network}&sequence=${sequence}`;
    for (let i = 0; i <= retries; i++) {
        try {
            const response = await fetch(apiEndpoint, {
                method: 'GET',
                headers: {
                    accept: 'application/json',
                },
            });

            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }

            const jsonResponse = await response.json();
            return jsonResponse.vaa;
        } catch (error) {
            if (i === retries) {
                throw error; // if it's the last retry, throw the error
            }

            // Wait for an exponentially increasing amount of time
            await new Promise((res) => setTimeout(res, delay * 2 ** i));
        }
    }
    throw new Error('Failed to fetch VAA after multiple retries');
};

async function processSequence(credentials, sequence) {
    const kvStore = new KeyValueStoreClient(credentials);
    const {notificationClient} = context;
    const expiry = await kvStore.get(`${network}-${sequence}`);
    // If the sequence is not in the KV store, return true to remove it from the network sequences array
    if (!expiry) return true;
    const expiryTimestamp = parseInt(expiry, 10); // Parse expiry string to integer
    const now = Math.floor(Date.now() / 1000);
    if (now >= expiryTimestamp) {
        console.log(`Sequence ${sequence} is ready, executing...`);
        // Fetch the VAA from the Cloudflare worker
        const vaa = await fetchVAA(sequence);
        if (!vaa) {
            console.log(`Failed to fetch VAA for sequence ${sequence}`);
            console.log(`Removing sequence ${sequence} from KV store...`);
            await kvStore.del(`${network}-${sequence}`);
            notificationClient.send({
                channelAlias: 'Parameter Changes to Slack',
                subject: `Failed to fetch VAA for sequence ${sequence} on ${network}`,
                message: `Removed ${network}-${sequence} from the KV store`,
            });
            return true; // Return true to remove the sequence from the network sequences array
        }

        // Initialize defender relayer provider and signer
        const client = new Defender(credentials);
        const provider = client.relaySigner.getProvider();
        const signer = client.relaySigner.getSigner(provider, {speed: 'fast'});

        // Create contract instance from the signer and use it to send a tx
        const contract = new ethers.Contract(
            tgAddress,
            temporalGovernorABI,
            signer,
        );
        try {
            const tx = await contract.executeProposal(vaa);
            if (tx) {
                console.log(`Called execute in ${tx.hash}`);
                console.log(`Removing sequence ${sequence} from KV store...`);
                await kvStore.del(`${network}-${sequence}`);
                notificationClient.send({
                    channelAlias: 'Parameter Changes to Slack',
                    subject: `Executed Queued Proposal ${sequence} on ${network}`,
                    message: `Successfully executed transaction: ${blockExplorer}${tx.hash}
                Removed ${network}-${sequence} from the KV store.`,
                });
                const {GOVBOT_WEBHOOK} = credentials.secrets;
                const moonwellEvent = new MoonwellEvent();
                const discordPayload = moonwellEvent.discordMessagePayload(
                    0x42b24e, // Green (Go color in Moonwell Guide)
                    `successfully executed`,
                    blockExplorer + tx.hash,
                    network,
                    sequence,
                    expiryTimestamp,
                );
                await moonwellEvent.sendDiscordMessage(
                    GOVBOT_WEBHOOK,
                    discordPayload,
                );
                return true;
            }
        } catch (error) {
            console.log(
                `Failed to execute sequence ${sequence}, error message: ${error}`,
            );
            console.log(`Removing sequence ${sequence} from KV store...`);
            await kvStore.del(`${network}-${sequence}`);
            notificationClient.send({
                channelAlias: 'Parameter Changes to Slack',
                subject: `Failed to Execute Queued Proposal ${sequence} on ${network}`,
                message: `Removed ${network}-${sequence} from the KV store`,
            });
            const {GOVBOT_WEBHOOK} = credentials.secrets;
            const moonwellEvent = new MoonwellEvent();
            const discordPayload = moonwellEvent.discordMessagePayload(
                0xe83938, // Red (Caution color in Moonwell Guide)
                `failed to execute`,
                'https://moonwell.fi/governance',
                network,
                sequence,
                expiryTimestamp,
            );
            await moonwellEvent.sendDiscordMessage(
                GOVBOT_WEBHOOK,
                discordPayload,
            );
            return true;
        }
    } else {
        console.log(
            `Sequence ${sequence} will be ready at ${expiry} (currently ${now}), skipping...`,
        );
        return false;
    }
}

// Entrypoint for the Autotask
exports.handler = async function (credentials, context) {
    console.log(`Checking for executable VAAs on ${network}...`);

    const kvStore = new KeyValueStoreClient(credentials);
    let sequences = (await kvStore.get(network))?.split(',');

    if (!sequences) {
        console.log('No VAAs found in KV store.');
        return;
    }

    console.log(`Found ${sequences.length} VAAs in KV store: ${sequences}`);

    let anyProcessed = false;
    for (let i = 0; i < sequences.length; i++) {
        const sequence = sequences[i];

        const isProcessed = await processSequence(
            credentials,
            sequence,
            context,
        );

        if (isProcessed) {
            anyProcessed = true;
            // If processed, remove this sequence from the array
            sequences.splice(i, 1);
            i--; // Adjust the index due to the removal
        }
    }

    // Store the updated array of strings back to the key/value store
    if (anyProcessed) await kvStore.put(network, sequences.join(','));
};
