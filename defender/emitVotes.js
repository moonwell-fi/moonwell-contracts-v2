// Script compatible with Defender v2
const {ethers} = require('ethers');
const {Defender} = require('@openzeppelin/defender-sdk');
const {KeyValueStoreClient} = require('defender-kvstore-client');
const axios = require('axios');

// const network = 'base'
// moonbeam is for Base testnet
const network = 'baseSepolia';

const voteCollectionAddress =
    network === 'base'
        ? '0xe0278B32c627FF6fFbbe7de6A18Ade145603e949' // TemporalGovernor on Base
        : '0xBdD86164da753C1a25e72603d266Dc1CC32e8acf'; // TemporalGovernor on Base Sepolia

const governorAddress =
    network === 'base'
        ? '0x9A8464C4C11CeA17e191653Deb7CdC1bE30F1Af4' // Multichain Governor on Moonbeam
        : '0xf152d75fe4cBB11AE224B94110c31F0bdDb55850'; // Multichain Governor on Moonbase

const voteCollectionABI = [
    'function emitVotes(uint256 proposalId) external payable',
    'function bridgeCostAll() external view returns (uint256)',
    'function proposalInformation(uint256 proposalId) external view returns(uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256)',
];

const governorABI = [
    'function liveProposals() external view returns (uint256[] memory)',
    'function state(uint256 proposalId) external view returns (uint8)',
    'function crossChainVoteCollectionPeriod() external view returns (uint256)',
];

// Block explorer URL
const blockExplorer =
    network === 'base'
        ? 'https://basescan.org/tx/'
        : 'https://sepolia.basescan.org/tx/';

class MoonwellEvent {
    async sendDiscordMessage(url, payload) {
        console.log('Sending Discord message...');
        if (!url) {
            throw new Error('Discord webhook url is invalid!');
        }

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

    discordMessagePayload(color, txURL, networkName, id) {
        const text = `Votes emmited for proposal ${id} on ${networkName}`;
        const details = `If the proposal reaches quorum, it will be executed automatically once the cross-chain vote collection period finishes.`;
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
            {
                name: 'Details',
                value: details,
                inline: false,
            },
        ];

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
        const numStr = num.toString();
        if (!numStr.includes('.')) {
            numStr = numStr + '.0';
        }
        const parts = numStr.split('.');
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        return parts
            .join('.')
            .replace(/(\.\d+[1-9])0+$/, '$1')
            .replace(/\.0+$/, '');
    }
}

async function storeProposal(kvStore, kvStoreValue, id) {}

// Entrypoint for the action
exports.handler = async function (event, context) {
    console.log('Received event:', JSON.stringify(event, null, 2));

    const moonbeamProvider =
        network == 'baseSepolia'
            ? new ethers.providers.JsonRpcProvider(
                  'https://rpc.testnet.moonbeam.network',
                  {
                      chainId: 1287,
                      name: 'moonbase-alpha',
                  },
              )
            : new ethers.providers.JsonRpcProvider(
                  'https://rpc.moonbeam.network',
                  {
                      chainId: 1284,
                      name: 'moonbeam',
                  },
              );

    const governor = new ethers.Contract(
        governorAddress,
        governorABI,
        moonbeamProvider,
    );

    const liveProposals = await governor.liveProposals();

    const client = new Defender(event);
    const provider = client.relaySigner.getProvider();
    const signer = await client.relaySigner.getSigner(provider, {
        speed: 'fast',
    });

    if (liveProposals.length == 0) {
        console.log('No live proposals found');
        return {};
    }

    const voteCollection = new ethers.Contract(
        voteCollectionAddress,
        voteCollectionABI,
        signer,
    );

    for (const proposalId of liveProposals) {
        const state = await governor.state(proposalId);
        console.log(`Proposal ${proposalId} state: ${state}`);

        const kvStore = new KeyValueStoreClient(event);
        const kvStoreValue = await kvStore.get(`${network}`);

        const ids = kvStoreValue?.split(',');

        if (ids && ids.includes(proposalId.toString())) {
            console.log(`Votes already emitted for proposal ${proposalId}`);
            continue;
        }

        if (state == 1) {
            console.log(
                `Proposal ${proposalId} is in the cross chain vote collection state`,
            );

            const proposalInformation =
                await voteCollection.proposalInformation(proposalId);

            let txHash;

            // only emit votes if proposal total votes is greater than 0
            if (proposalInformation[5] > 0) {
                try {
                    const bridgeCost = await voteCollection.bridgeCostAll();

                    const gasEstimate =
                        await voteCollection.estimateGas.emitVotes(proposalId, {
                            value: bridgeCost,
                        });

                    // Add a buffer to the gas estimate
                    const gasLimit = gasEstimate.add(gasEstimate.div(5)); // Adding 20% extra gas as a buffer

                    const tx = await voteCollection.emitVotes(proposalId, {
                        value: bridgeCost,
                        gasLimit: gasLimit,
                    });
                    console.log(`Transaction hash: ${tx.hash}`);

                    if (kvStoreValue) {
                        kvStoreValue += `,${id}`;
                    } else {
                        kvStoreValue = `${id}`;
                    }

                    console.log(`Storing proposal ${id} in KV store...`);
                    await kvStore.put(`${network}`, kvStoreValue);
                    console.log(`Updated KV store value for ${network}`);

                    txHash = tx.hash;
                } catch (error) {
                    console.error(
                        `Error emitting votes for proposal ${proposalId}: ${error.message}`,
                    );
                    continue;
                }

                // Slack
                const {notificationClient} = context;
                notificationClient.send({
                    channelAlias: 'Parameter Changes to Slack',
                    subject: `Votes emitted for proposal ${proposalId} on ${network}`,
                    message: `If the proposal reaches quorum, it will be executed automatically once the cross-chain vote collection period finishes.`,
                });

                // Discord
                const {GOVBOT_WEBHOOK} = event.secrets;
                const moonwellEvent = new MoonwellEvent();
                const discordPayload = moonwellEvent.discordMessagePayload(
                    0x00ff00,
                    blockExplorer + txHash,
                    network,
                    proposalId,
                );
                await moonwellEvent.sendDiscordMessage(
                    GOVBOT_WEBHOOK,
                    discordPayload,
                );

                return {tx: txHash};
            } else {
                console.log(`Proposal ${proposalId} has no votes, skipping...`);
            }
        } else {
            console.log(
                `Proposal ${proposalId} is not in the cross chain vote collection state, skipping...`,
            );
        }
    }

    return {};
};
