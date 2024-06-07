const {ethers} = require('ethers');
const {Defender} = require('@openzeppelin/defender-sdk');
const {KeyValueStoreClient} = require('defender-kvstore-client');
const axios = require('axios');

const network = 'moonbeam';
const senderNetwork = network === 'moonbeam' ? 'base' : 'baseSepolia';

const governorAddress =
    network === 'moonbeam'
        ? '0x9A8464C4C11CeA17e191653Deb7CdC1bE30F1Af4'
        : '0xf152d75fe4cBB11AE224B94110c31F0bdDb55850';

const blockExplorer =
    network === 'moonbeam'
        ? 'https://moonbeam.moonscan.io/tx/'
        : 'https://moonbase.moonscan.io/tx/';

const governorABI = [
    'function liveProposals() external view returns (uint256[] memory)',
    'function state(uint256 proposalId) external view returns (uint8)',
    'function crossChainVoteCollectionPeriod() external view returns (uint256)',
    'function execute(uint256 proposalId) external payable',
];

class MoonwellEvent {
    async sendDiscordMessage(url, payload) {
        console.log('Sending Discord message...');
        if (!url) throw new Error('Discord webhook url is invalid!');
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

    discordMessagePayload(color, message, details) {
        return {
            content: '',
            embeds: [
                {
                    title: `${message}`,
                    color: color,
                    fields: [{name: 'Details', value: details, inline: false}],
                },
            ],
        };
    }

    discordFormatLink(text, url) {
        return `[${text}](${url})`;
    }

    numberWithCommas(num) {
        if (!num.includes('.')) num = num + '.0';
        const parts = num.toString().split('.');
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        return parts
            .join('.')
            .replace(/(\.\d+[1-9])0+$/, '$1')
            .replace(/\.0+$/, '');
    }
}

async function processProposal(governor, secrets, kvStore, id, context) {
    console.log(`Proposal ${id} is ready, executing...`);

    const {notificationClient} = context;
    const state = await governor.state(id);
    let subject, message, shouldDelete, color;

    if (state == 4) {
        try {
            const tx = await governor.execute(id);
            console.log(`Called execute in ${tx.hash}`);
            subject = `Executed Proposal ${id} on ${network}`;
            message = `Successfully executed transaction: ${blockExplorer}${tx.hash}.`;
            shouldDelete = true;
            color = 0x42b24e; // Green
        } catch (error) {
            console.log(
                `Failed to execute proposal ${id}, error message: ${error}`,
            );
            subject = `Failed to Execute Proposal ${id} on ${network}`;
            message = `Manual execution required.`;
            shouldDelete = true;
            color = 0xe83938; // Red
        }
    } else if (state == 2 || state == 3 || state == 5) {
        subject = `Proposal ${id} is ${state == 2 ? 'canceled' : state == 3 ? 'defeated' : 'executed'}`;
        message = `Removed from KV store.`;
        shouldDelete = true;
        color = 0xffa500; // Orange
    } else {
        console.log(
            `Proposal ${id} is still in the cross chain vote collection state, skipping...`,
        );
        return false;
    }

    notificationClient.send({
        channelAlias: 'Parameter Changes to Slack',
        subject,
        message,
    });

    const {GOVBOT_WEBHOOK} = secrets;
    const moonwellEvent = new MoonwellEvent();
    const discordPayload = moonwellEvent.discordMessagePayload(
        color,
        subject,
        message,
    );
    await moonwellEvent.sendDiscordMessage(GOVBOT_WEBHOOK, discordPayload);

    if (shouldDelete) await kvStore.del(`${network}-${id}`);

    return shouldDelete;
}

exports.handler = async function (credentials, context) {
    console.log(`Checking for executable proposals on ${network}...`);

    const client = new Defender(credentials);
    const provider = client.relaySigner.getProvider();
    const signer = await client.relaySigner.getSigner(provider, {
        speed: 'fast',
    });
    const governor = new ethers.Contract(governorAddress, governorABI, signer);
    const liveProposals = await governor.liveProposals();

    const kvStore = new KeyValueStoreClient(credentials);
    const kvStoreValue = await kvStore.get(`${senderNetwork}`);
    console.log(`kvStoreValue: ${kvStoreValue}`);

    let ids = kvStoreValue?.split(',');

    if (!ids) {
        console.log('No proposal found in KV store.');
        return;
    }

    console.log(`Found ${ids.length} proposals in KV store: ${ids}`);

    let anyProcessed = false;
    for (let i = 0; i < ids.length; i++) {
        const id = ids[i];
        const isProcessed = await processProposal(
            governor,
            credentials.secrets,
            kvStore,
            id,
            context,
        );
        if (isProcessed) {
            anyProcessed = true;
            ids.splice(i, 1);
            i--;
        }
    }

    if (anyProcessed) await kvStore.put(senderNetwork, ids.join(','));
};
