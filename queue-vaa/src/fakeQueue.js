const {KeyValueStoreClient} = require('defender-kvstore-client');
const axios = require('axios');

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
        text,
        txURL,
        networkName,
        sequence,
        timestamp,
        details,
    ) {
        const friendlyNetworkName =
            networkName === 'moonbase' ? 'Base Goerli' : 'Base';
        const baseFields = [
            {
                name: 'Network',
                value: friendlyNetworkName,
                inline: true,
            },
            {
                name: 'Sequence ID',
                value: sequence,
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

exports.handler = async function (credentials, context) {
    const kvStore = new KeyValueStoreClient(credentials);
    const {notificationClient} = context;

    const network = 'moonbase'; // Change to 'moonbase' for Base Goerli
    const sequence = '35'; // Change to the sequence you want to insert
    const timestamp = 1692616508; // Change to the timestamp you want to insert

    console.log(`Inserting a queued VAA key/value on ${network}...`);
    await kvStore.put(`${network}-${sequence}`, timestamp.toString());
    let value = await kvStore.get(network);
    console.log(`Initial KV store value for ${network}: ${value}`);
    if (value !== null) {
        value += `,${sequence}`;
    } else {
        value = sequence;
    }
    await kvStore.put(network, value);
    console.log(`Updated KV store value for ${network}: ${value}`);
    console.log(`Stored ${network}-${sequence} with expiry ${timestamp}`);
    notificationClient.send({
        channelAlias: 'Parameter Changes to Slack',
        subject: `Inserted queued VAA ${sequence} on ${network}`,
        message: `Inserted a queued key/value at future timestamp ${timestamp}, stored sequence value ${value} for ${network}`,
    });
    const {GOVBOT_WEBHOOK} = credentials.secrets;
    const moonwellEvent = new MoonwellEvent();
    const payload = moonwellEvent.discordMessagePayload(
        0x42b24e, // Green (Go color in Moonwell Guide)
        `Scheduled cross-chain execution of proposal ${sequence} on ${network}`,
        'https://moonwell.fi/governance',
        network,
        sequence,
        timestamp,
        `Upon successful completion of proposal ${sequence}, it will be automatically executed on the ${network} network exactly 24 hours from now.`,
    );
    await moonwellEvent.sendDiscordMessage(GOVBOT_WEBHOOK, payload);
};

// To run locally (this code will not be executed in Autotasks)
if (require.main === module) {
    const {API_KEY: apiKey, API_SECRET: apiSecret} = process.env;
    exports
        .handler({apiKey, apiSecret})
        .then(() => process.exit(0))
        .catch((error) => {
            console.error(error);
            process.exit(1);
        });
}
