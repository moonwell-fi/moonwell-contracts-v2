/* eslint-disable @typescript-eslint/no-var-requires */
// Script compatible with Defender v2
const {ethers} = require('ethers');
const {Defender} = require('@openzeppelin/defender-sdk');
const {KeyValueStoreClient} = require('defender-kvstore-client');
const axios = require('axios');

//const network = 'optimism'
const network = 'base';

// Function to calculate the timestamp for the next Wednesday
function getCurrentWeekWednesdayTimestamp() {
    const now = new Date();
    const dayOfWeek = now.getDay(); // Monday is 1
    const daysUntilWednesday = (3 - dayOfWeek + 7) % 7; // Wednesday is 3
    const thisWeekWednesday = new Date(now);
    thisWeekWednesday.setDate(now.getDate() + daysUntilWednesday);
    thisWeekWednesday.setHours(0, 5, 0, 0); // Set to 00:05 of this Wednesday
    return Math.floor(thisWeekWednesday.getTime() / 1000);
}


async function storeEntries(event) {
    const { to, amount } = event.request.body.matchReasons[0].params;

    console.log('Storing entries in KV store...');
    const kvStore = new KeyValueStoreClient(event);
    let value = await kvStore.get(to);

    console.log(`Initial KV store value for ${to}: ${value}`);

  //  if (value !== null) {
  //    console.log("Current rewards epoch haven't finished yet, triggering notification clients..")
  //    return;
  //  }

  // split the amount into 4 parts
  const splitAmount = amount.div(4);

  for (let i = 0; i < 4; i++) {
      const currentWeekWednesdayTimestamp = getCurrentWeekWednesdayTimestamp();
      const timestamp = currentWeekWednesdayTimestamp + i * 604800; // Increment by weeks
      const valueToStore = `${splitAmount}-${timestamp}`;

      console.log( "Storing value: ", valueToStore);
      // log timestamp in human readable format
      console.log("Timestamp:" new Date(timestamp * 1000).toUTCString());
  
      // Append the new value to the existing values
      if (existingValues) {
          existingValues += `,${valueToStore}`;
      } else {
          existingValues = valueToStore;
      }
  }

  // Store the updated values back in the key
  await kvStore.put(to, existingValues);
  console.log(`Stored values for ${to}: ${existingValues}`);
}

// Entrypoint for the action
exports.handler = async function (event, context) {
    console.log('Received event:', JSON.stringify(event.request.body, null, 2));

    await storeEntries(event);
};
