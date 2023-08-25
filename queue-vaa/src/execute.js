const { ethers } = require("ethers");
const { 
  DefenderRelaySigner,
  DefenderRelayProvider
} = require('defender-relay-client/lib/ethers');
const { KeyValueStoreClient } = require('defender-kvstore-client');

const temporalGovernorABI = [
  "function queueProposal(bytes VAA)",
  "function executeProposal(bytes VAA)",
]

// Use Moonbeam for Base
const network = 'moonbeam'
// Use Moonbase Alpha for Base Goerli
// const network = 'moonbase'

const tgAddress =
  network === 'moonbase' ? '0xBaA4916ACD2d3Db77278A377f1b49A6E1127d6e6' // TemporalGovernor on Base Goerli
  : '0x8b621804a7637b781e2BbD58e256a591F2dF7d51' // TemporalGovernor on Base

// Block explorer URL
const blockExplorer = 
  network === 'moonbase' ? 'https://goerli.basescan.org/tx/'
  : 'https://basescan.org/tx/'

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

async function processSequence(credentials, sequence, context) {
  const kvStore = new KeyValueStoreClient(credentials);
  const { notificationClient } = context;
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
        message: `Removed ${network}-${sequence} from the KV store`
      });
      return true; // Return true to remove the sequence from the network sequences array
    }

    // Initialize defender relayer provider and signer
    const provider = new DefenderRelayProvider(credentials);
    const signer = new DefenderRelaySigner(credentials, provider, { speed: 'fast' });

    // Create contract instance from the signer and use it to send a tx
    const contract = new ethers.Contract(tgAddress, temporalGovernorABI, signer);
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
Removed ${network}-${sequence} from the KV store.`
        });
        return true;
      }
    } catch (error) {
      console.log(`Failed to execute sequence ${sequence}, error message: ${error}`);
      console.log(`Removing sequence ${sequence} from KV store...`);
      await kvStore.del(`${network}-${sequence}`);
      notificationClient.send({
        channelAlias: 'Parameter Changes to Slack',
        subject: `Failed to Execute Queued Proposal ${sequence} on ${network}`,
        message: `Removed ${network}-${sequence} from the KV store`
      });
      return true;
    }
  } else {
    console.log(`Sequence ${sequence} will be ready at ${expiry} (currently ${now}), skipping...`);
    return false;
  }
}

// Entrypoint for the Autotask
exports.handler = async function(credentials, context) {
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
    
    const isProcessed = await processSequence(credentials, sequence, context);

    if (isProcessed) {
      anyProcessed = true;
      // If processed, remove this sequence from the array
      sequences.splice(i, 1);
      i--; // Adjust the index due to the removal
    }
  }

  // Store the updated array of strings back to the key/value store
  if (anyProcessed) await kvStore.put(network, sequences.join(','));
}

// To run locally (this code will not be executed in Autotasks)
if (require.main === module) {
  const { API_KEY: apiKey, API_SECRET: apiSecret } = process.env;
  exports.handler({ apiKey, apiSecret })
    .then(() => process.exit(0))
    .catch(error => { console.error(error); process.exit(1); });
}
