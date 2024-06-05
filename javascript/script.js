const fs = require('fs');

// Function to order keys alphabetically
function orderKeys(obj) {
    if (typeof obj !== 'object' || obj === null) return obj;
    if (Array.isArray(obj)) return obj.map(orderKeys);
    return Object.keys(obj)
        .sort()
        .reduce((acc, key) => {
            acc[key] = orderKeys(obj[key]);
            return acc;
        }, {});
}

// Read the JSON file
const jsonData = fs.readFileSync('utils/Addresses.json', 'utf8');
const parsedData = JSON.parse(jsonData);

// Order keys
const orderedData = orderKeys(parsedData);

// Pretty print
console.log(JSON.stringify(orderedData, null, 2));
