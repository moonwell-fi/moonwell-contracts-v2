const { KeyValueStoreClient } = require('defender-kvstore-client');

exports.handler = async function(credentials, context) {
  const kvStore = new KeyValueStoreClient(credentials);
  const { notificationClient } = context;

  const network='moonbase'; // Change to 'moonbase' for Base Goerli
  const sequence='35'; // Change to the sequence you want to insert
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
    message: `Inserted a queued key/value at future timestamp ${timestamp}, stored sequence value ${value} for ${network}`
  });
}

// To run locally (this code will not be executed in Autotasks)
if (require.main === module) {
  const { API_KEY: apiKey, API_SECRET: apiSecret } = process.env;
  exports.handler({ apiKey, apiSecret })
    .then(() => process.exit(0))
    .catch(error => { console.error(error); process.exit(1); });
}
