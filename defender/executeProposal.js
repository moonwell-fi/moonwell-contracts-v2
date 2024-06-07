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

const governorAddress =
    network === 'moonbeam'
        ? '0x9A8464C4C11CeA17e191653Deb7CdC1bE30F1Af4' // Multichain Governor on Moonbeam
        : '0xf152d75fe4cBB11AE224B94110c31F0bdDb55850'; // Multichain Governor on Moonbase

// Block explorer URL
const blockExplorer =
    network === 'moonbeam'
        ? 'https://moonbeam.moonscan.io/tx/'
        : 'https://moonbase.moonscan.io/tx/';

const governorABI = [
    'function liveProposals() external view returns (uint256[] memory)',
    'function state(uint256 proposalId) external view returns (uint8)',
    'function crossChainVoteCollectionPeriod() external view returns (uint256)',
];

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

    discordMessagePayload(color, txURL, networkName, id, timestamp) {
        const text = `Proposal ${id} executed on ${networkName}`;
        const baseFields = [
            {
                name: 'Network',
                value: networkName,
                inline: true,
            },
            {
                name: 'Proposal',
                value: `${id}`,
                inline: true,
            },
        ];

        if (timestamp && timestamp > 0) {
            baseFields.push({
                name: 'Will be executed at',
                value: `<t:${timestamp}>`,
                inline: true,
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

async function processProposal(credentials, id, context) {
    const kvStore = new KeyValueStoreClient(credentials);
    const {notificationClient} = context;
    const expiry = await kvStore.get(`proposals-${network}-${id}`);
    // If the id is not in the KV store, return true to remove it from the network proposals ids array
    if (!expiry) return true;
    const expiryTimestamp = parseInt(expiry, 10); // Parse expiry string to integer
    const now = Math.floor(Date.now() / 1000);
    if (now >= expiryTimestamp) {
        console.log(`Proposal ${id} is ready, executing...`);

        const provider = new DefenderRelayProvider(credentials);
        const signer = new DefenderRelaySigner(credentials, provider, {
            speed: 'fast',
        });

        const governor = new ethers.Contract(
            governorAddress,
            governorABI,
            provider,
        );

        const state = await governor.state(proposalId);

        // Proposal is succeeded
        if (state == 4) {
            try {
                const tx = await governor.execute(id);

                if (tx) {
                    console.log(`Called execute in ${tx.hash}`);
                    console.log(`Removing proposal ${id} from KV store...`);
                    await kvStore.del(`proposals-${network}-${id}`);
                    notificationClient.send({
                        channelAlias: 'Parameter Changes to Slack',
                        subject: `Executed Proposal ${id} on ${network}`,
                        message: `Successfully executed transaction: ${blockExplorer}${tx.hash}.
              Removed proposals-${network}-${id} from the KV store.`,
                    });

                    const {GOVBOT_WEBHOOK} = credentials.secrets;
                    const moonwellEvent = new MoonwellEvent();

                    const discordPayload = moonwellEvent.discordMessagePayload(
                        0x42b24e, // Green (Go color in Moonwell Guide)
                        `successfully executed`,
                        blockExplorer + tx.hash,
                        network,
                        id,
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
                    `Failed to execute proposal ${id}, error message: ${error}`,
                );
                console.log(`Removing proposal ${id} from KV store...`);
                await kvStore.del(`proposals-${network}-${id}`);
                notificationClient.send({
                    channelAlias: 'Parameter Changes to Slack',
                    subject: `Failed to Execute Proposal ${id} on ${network}`,
                    message: `Removed proposals-${network}-${id} from the KV store`,
                });
                const {GOVBOT_WEBHOOK} = credentials.secrets;
                const moonwellEvent = new MoonwellEvent();
                const discordPayload = moonwellEvent.discordMessagePayload(
                    0xe83938, // Red (Caution color in Moonwell Guide)
                    `failed to execute`,
                    'https://moonwell.fi/governance',
                    network,
                    id,
                    expiryTimestamp,
                );
                await moonwellEvent.sendDiscordMessage(
                    GOVBOT_WEBHOOK,
                    discordPayload,
                );
                return true;
            }

            // Proposal is defeated, canceled or executed
        } else if (state == 2 || state == 3 || state == 5) {
            console.log(`Removing proposal ${id} from KV store...`);

            await kvStore.del(`proposals-${network}-${id}`);

            notificationClient.send({
                channelAlias: 'Parameter Changes to Slack',
                subject: `Removed Proposal ${id} from ${network} as it is ${state == 2 ? 'defeated' : state == 3 ? 'canceled' : 'executed'}`,
                message: `Removed ${network}-${id} from the KV store`,
            });

            return true; // Return true to remove the id from the proposals array
        }
    } else {
        console.log(
            `Proposal ${id} will finish the vote collection period at ${expiry} (currently ${now}), skipping...`,
        );
        return false;
    }
}

// Entrypoint for the Autotask
exports.handler = async function (credentials, context) {
    console.log(`Checking for executable proposals on ${network}...`);

    const kvStore = new KeyValueStoreClient(credentials);
    const data = await kvStore.get(`proposals-${network}-`);
    console.log(`Data: ${data}`);
    let ids = data?.split(',');

    if (!ids) {
        console.log('No proposal found in KV store.');
        return;
    }

    console.log(`Found ${ids.length} proposals in KV store: ${ids}`);

    let anyProcessed = false;
    for (let i = 0; i < ids.length; i++) {
        const id = ids[i];

        const isProcessed = await processProposal(credentials, id, context);

        if (isProcessed) {
            anyProcessed = true;
            // If processed, remove this sequence from the array
            ids.splice(i, 1);
            i--; // Adjust the index due to the removal
        }
    }

    // Store the updated array of strings back to the key/value store
    if (anyProcessed) await kvStore.put(network, ids.join(','));
};
