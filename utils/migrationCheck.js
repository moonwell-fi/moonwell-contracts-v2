/// TODO delete this file once migration is complete
const fs = require('fs');
const path = require('path');

// Read the original Addresses.json file
const addresses = require('./Addresses.json');

// Function to read all <chainid>.json files
function readChainFiles() {
    const files = fs
        .readdirSync(__dirname)
        .filter((file) => file.endsWith('.json') && file !== 'Addresses.json');
    const chainFiles = {};

    files.forEach((file) => {
        const chainId = path.basename(file, '.json');
        const data = require(path.join(__dirname, file));
        chainFiles[chainId] = data;
    });

    return chainFiles;
}

// Function to cross-check addresses
function crossCheckAddresses(addresses, chainFiles) {
    const originalAddressesMap = {};
    const chainIdAddressesMap = {};

    // Create a map from original Addresses.json
    addresses.forEach((address) => {
        const {chainId, ...rest} = address;
        if (!originalAddressesMap[chainId]) {
            originalAddressesMap[chainId] = [];
        }
        originalAddressesMap[chainId].push(rest);
    });

    // Create a map from <chainid>.json files
    Object.keys(chainFiles).forEach((chainId) => {
        chainIdAddressesMap[chainId] = chainFiles[chainId];
    });

    // Check from Addresses.json to <chainid>.json files
    Object.keys(originalAddressesMap).forEach((chainId) => {
        originalAddressesMap[chainId].forEach((originalAddress) => {
            const match = chainIdAddressesMap[chainId]?.find(
                (chainAddress) =>
                    JSON.stringify(chainAddress) ===
                    JSON.stringify(originalAddress),
            );
            if (!match) {
                throw new Error(
                    `Missing address from chain file ${chainId}.json: ${JSON.stringify(originalAddress)}`,
                );
            }
        });
    });

    // Check from <chainid>.json files to Addresses.json
    Object.keys(chainIdAddressesMap).forEach((chainId) => {
        chainIdAddressesMap[chainId].forEach((chainAddress) => {
            const match = originalAddressesMap[chainId]?.find(
                (originalAddress) =>
                    JSON.stringify(originalAddress) ===
                    JSON.stringify(chainAddress),
            );
            if (!match) {
                throw new Error(
                    `Extra address in chain file ${chainId}.json: ${JSON.stringify(chainAddress)}`,
                );
            }
        });
    });

    console.log('Cross-checking complete. All addresses match.');
}

// Read the chain files and perform the cross-check
const chainFiles = readChainFiles();
crossCheckAddresses(addresses, chainFiles);
