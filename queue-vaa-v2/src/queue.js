/* eslint-disable @typescript-eslint/no-var-requires */
const { ethers } = require("ethers");
const { Defender } = require('@openzeppelin/defender-sdk');
const axios = require('axios');

// moonbeam is for Base Mainnet
//const network = 'moonbeam'
// moonbeam is for Base testnet
 const network = 'moonbase'

const temporalGovernorABI = [
  "function queueProposal(bytes VAA)",
  "function executeProposal(bytes VAA)",
]

const tgAddress =
    network === 'moonbase'
        ? '0x5713dd9a2b2ce515cf9232f48b457aebfb04b292' // TemporalGovernor on Base Sepolia
        : '0x8b621804a7637b781e2BbD58e256a591F2dF7d51'; // TemporalGovernor on Base


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


// Entrypoint for the action
exports.handler = async function (event) {
  if (!event.request || !event.request.body) throw new Error(`Missing payload`);
  const { matchReasons, request, signature } = event.request.body;

  const sequence = payload.matchReasons[0].params.sequence;
  const vaa = await fetchVAA(sequence);

  const client = new Defender(event);

  const provider = client.relaySigner.getProvider();
  const signer = client.relaySigner.getSigner(provider, { speed: 'fast' });

  const governor= new ethers.Contract(tgAddress, temporalGovernorABI, signer);

  const tx = await contract.queueProposal(vaa);
  console.log(`Called queueProposal in ${tx.hash}`);

}

// To run locally (this code will not be executed in Autotasks)
if (require.main === module) {
  const { API_KEY: apiKey, API_SECRET: apiSecret } = process.env;
  exports.handler({ ...mockEvent, apiKey, apiSecret })
    .then(() => process.exit(0))
    .catch(error => { console.error(error); process.exit(1); });
}
