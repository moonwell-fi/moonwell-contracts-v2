/// TODO delete this file once migration is complete
const fs = require('fs');
const path = require('path');

// Read the Addresses.json file
const addresses = require('./Addresses.json');

// Function to process addresses and create new files
function processAddresses(addresses) {
    const chainIdMap = {};

    // Group addresses by chainId
    addresses.forEach((address) => {
        const {chainId, ...rest} = address;
        if (!chainIdMap[chainId]) {
            chainIdMap[chainId] = [];
        }
        chainIdMap[chainId].push(rest);
    });

    // Create a new file for each chainId
    Object.keys(chainIdMap).forEach((chainId) => {
        const filePath = path.join(__dirname, `${chainId}.json`);
        fs.writeFileSync(
            filePath,
            JSON.stringify(chainIdMap[chainId], null, 2),
        );
        console.log(`Created file: ${filePath}`);
    });

    console.log('Processing complete.');
}

// Call the function with the addresses
processAddresses(addresses);
