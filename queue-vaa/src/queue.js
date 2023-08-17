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

async function storeVAA(event, sequence) {
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
  let timestamp = Math.floor(Date.now() / 1000);
  // On testnet, there is no 24 hour timelock
  // timestamp += 60 * 60 * 24 // 24 hours
  await kvStore.put(`${network}-${sequence}`, timestamp.toString());
  console.log(`Stored ${network}-${sequence} with expiry ${timestamp}`);
}

// Entrypoint for the Autotask
exports.handler = async function(event) {
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
  await storeVAA(event, sequence);
  return { tx: tx.hash };
}

// To run locally (this code will not be executed in Autotasks)
if (require.main === module) {
  const { API_KEY: apiKey, API_SECRET: apiSecret } = process.env;
  exports.handler({ apiKey, apiSecret })
    .then(() => process.exit(0))
    .catch(error => { console.error(error); process.exit(1); });
}
