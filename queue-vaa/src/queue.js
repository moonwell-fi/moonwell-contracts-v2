const { ethers } = require("ethers");
const { 
  DefenderRelaySigner,
  DefenderRelayProvider
} = require('defender-relay-client/lib/ethers');
const { KeyValueStoreClient } = require('defender-kvstore-client');
const axios = require('axios');

const temporalGovernorABI = [
  "function queueProposal(bytes VAA)",
  "function executeProposal(bytes VAA)",
]

// moonbeam is for Base Mainnet
const network = 'moonbeam'
// moonbeam is for Base testnet
// const network = 'moonbase'

const tgAddress =
<<<<<<< Updated upstream
  network === 'moonbase' ? '0xBaA4916ACD2d3Db77278A377f1b49A6E1127d6e6' // TemporalGovernor on Base Goerli
  : '0x8b621804a7637b781e2BbD58e256a591F2dF7d51' // TemporalGovernor on Base

// Block explorer URL
const blockExplorer = 
  network === 'moonbase' ? 'https://goerli.basescan.org/tx/'
  : 'https://basescan.org/tx/'
=======
    network === 'moonbase'
        ? '0xc01EA381A64F8BE3bDBb01A7c34D809f80783662' // TemporalGovernor on Base Sepolia
        : '0x8b621804a7637b781e2BbD58e256a591F2dF7d51'; // TemporalGovernor on Base

// Block explorer URL
const blockExplorer =
    network === 'moonbase'
        ? 'https://sepolia.basescan.org/tx/'
        : 'https://basescan.org/tx/';
>>>>>>> Stashed changes

class MoonwellEvent {
  async sendDiscordMessage(url, payload) {
    console.log("Sending Discord message...");
    if (!url) {
      throw new Error("Discord webhook url is invalid!");
    }
    console.log("SENDING", JSON.stringify(payload, null, 2));
    try {
      const response = await axios.post(url, payload, {
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
        },
      });
      console.log(`Status code: ${response.status}`);
      console.log(`Response data: ${JSON.stringify(response.data, null, 2)}`);
    } catch (error) {
      console.error(`Error message: ${error.message}`);
    }
    console.log("Sent Discord message!");
  }

  discordMessagePayload(color, txURL, networkName, sequence, timestamp) {
    const mipNumber = sequence - 1;
    let mipString = '';
    if (mipNumber < 10) {
      mipString = `MIP-B0${mipNumber}`;
    } else {
      mipString = `MIP-B${mipNumber}`;
    }
    const text = `Scheduled cross-chain execution of ${mipString} on ${networkName}`;
    const details = `Upon successful completion of ${mipString}, it should be automatically executed on the ${networkName} network exactly 24 hours from now.`
    const baseFields = [
      {
        "name": "Network",
        "value": networkName,
        "inline": true
      },
      {
        "name": "Proposal",
        "value": mipString,
        "inline": true
      }
    ];

    if ((timestamp) && (timestamp > 0)) {
      baseFields.push({
        "name": "Will be executed at",
        "value": `<t:${timestamp}>`,
        "inline": true
      });
    }

    if (details) {
      baseFields.push({
        "name": "Details",
        "value": details,
        "inline": false
      });
    }

    return {
      "content": "",
      "embeds": [
        {
          "title": `${text}`,
          "color": color,
          "fields": baseFields,
          "url": txURL
        }
      ]
    };
  }

  discordFormatLink(text, url) {
    return `[${text}](${url})`
  }

  numberWithCommas(num) {
    if (!num.includes('.')) {
      num = num + '.0'
    }
    const parts = num.toString().split(".");
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return parts.join(".")
      .replace(/(\.\d+[1-9])0+$/, '$1')
      .replace(/\.0+$/, '')
  }
}

const fetchVAA = async (sequence, retries = 5, delay = 2000) => {
  const apiEndpoint = `https://vaa-fetch.moonwell.workers.dev/?network=${network}&sequence=${sequence}`;
  for (let i = 0; i <= retries; i++) {
    try {
      const response = await fetch(apiEndpoint, {
        method: 'GET',
        headers: {
          'accept': 'application/json'
        }
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
      await new Promise(res => setTimeout(res, delay * (2 ** i)));
    }
  }
  throw new Error("Failed to fetch VAA after multiple retries");
}

async function storeVAA(event, sequence, timestamp) {
  console.log('Storing sequence in KV store...');
  const kvStore = new KeyValueStoreClient(event);
  let value = await kvStore.get(network);
  console.log(`Initial KV store value for ${network}: ${value}`);
  if (value !== null) {
    value += `,${sequence}`;
  } else {
    value = sequence;
  }
  await kvStore.put(network, value);
  console.log(`Updated KV store value for ${network}: ${value}`);
  await kvStore.put(`${network}-${sequence}`, timestamp.toString());
  console.log(`Stored ${network}-${sequence} with expiry ${timestamp}`);
}

// Entrypoint for the Autotask
exports.handler = async function(event, context) {
  const { notificationClient } = context;
  const payload = event.request.body;
  const matchReasons = payload.matchReasons;
  const sentinel = payload.sentinel;
  const transaction = payload.transaction;
  const abi = sentinel.abi;

  const sequence = payload.matchReasons[0].params.sequence;

  // Fetch the VAA from the Cloudflare worker
  const vaa = await fetchVAA(sequence);

  // Initialize defender relayer provider and signer
  const provider = new DefenderRelayProvider(event);
  const signer = new DefenderRelaySigner(event, provider, { speed: 'fast' });

  // Create contract instance from the signer and use it to send a tx
  const contract = new ethers.Contract(tgAddress, temporalGovernorABI, signer);
  const tx = await contract.queueProposal(vaa);
  console.log(`Called queueProposal in ${tx.hash}`);
  let timestamp = Math.floor(Date.now() / 1000);
  // On testnet, there is no 24 hour timelock
  timestamp += 60 * 60 * 24 + 60 // 24 hours + 1 minute for buffer
  await storeVAA(event, sequence, timestamp);
  notificationClient.send({
    channelAlias: 'Parameter Changes to Slack',
    subject: `Inserted queued VAA ${sequence} on ${network}`,
    message: `Inserted a queued key/value at future timestamp ${timestamp} for ${network}`
  });
  const { GOVBOT_WEBHOOK } = event.secrets;
  const moonwellEvent = new MoonwellEvent();
  const friendlyNetworkName = 
    network === 'moonbase' ? 'Base Goerli'
    : 'Base'
  const discordPayload = moonwellEvent.discordMessagePayload(
    0x00ff00,
    blockExplorer + tx.hash,
    friendlyNetworkName,
    sequence,
    timestamp
  );
  await moonwellEvent.sendDiscordMessage(GOVBOT_WEBHOOK, discordPayload);
  return { tx: tx.hash };
}

// To run locally (this code will not be executed in Autotasks)
if (require.main === module) {
  const { API_KEY: apiKey, API_SECRET: apiSecret } = process.env;
  exports.handler({ apiKey, apiSecret })
    .then(() => process.exit(0))
    .catch(error => { console.error(error); process.exit(1); });
}
