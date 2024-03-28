const jsonData = require('./utils/Addresses.json');

for (const x of jsonData) {
    if (typeof x.addr !== "string") {
        console.log(`Error: address is not a string ${x.addr}`);
    }
    if (typeof x.name !== "string") {
        console.log(`Error: name is not a string ${x.name}`);
    }
    if (isNaN(x.chainId)) {
        console.log(`Error: chainId is not a number ${x.chainId}`);
    }
    console.log("checking element")
}
