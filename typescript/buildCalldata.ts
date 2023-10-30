import * as fs from 'fs';
import * as abi from 'ethereumjs-abi';
import * as jsonData from './../proposals/MIP06.json';
import BigNumber from "bignumber.js";

/// @notice this is a script to generate calldata for temporal governor on BASE mainnet ONLY
/// DO NOT use this script to generate calldata for any other network

/// TODO:
///     add support for multiple networks
///     add support for debugging output
///     add support for logging out description in debug mode

// Load address data
const addressData = JSON.parse(fs.readFileSync('./../utils/Addresses.json', 'utf8'));
const addressMap: { [key: string]: string } = {};

/// max chainId is 2^53 - 1, so this will safely load addresses from BASE mainnet and all testnets
addressData.forEach((item: { name: string; addr: string, chainId: number }) => {
    /// only load addresses from BASE mainnet
    if (item.chainId == 8453) {
        addressMap[item.name] = item.addr;
    }
});

// Function to replace variables in a string with their corresponding address
// function replaceVariablesWithAddress(str: string): string {
//     if str.match()
//     return str.replace(/^[a-zA-Z]+(_[a-zA-Z]+)*$/g, (_, variable) => addressMap[variable] || `{${variable}}`);
// }

function replaceVariablesWithAddress(str: string): string {
    const regex = /^\{[a-zA-Z]+(_[a-zA-Z]+)*\}$/g
    if (regex.test(str)) {
        console.log("str matched: ", str);

        const key = str.slice(1, -1);  // Remove the front and back braces
        return addressMap[key];
    }

    console.log("str did not match: ", str);

    return str;
}


/// returns calldata of abi encoded method with arguments
function encodeAbi(method: string, args: any[]): Buffer {
    const splitMethod = method.split('(');
    const methodName = splitMethod[0];
    const types = splitMethod[1].slice(0, -1).split(',');

    // console.log("types: ", types);

    const encodedMethod = abi.methodID(methodName, types);
    const encodedParams = abi.rawEncode(types, args);

    // console.log("encodedMethod: ", encodedMethod.toString('hex'));
    // console.log("encodedParams: ", encodedParams.toString('hex'));
    // console.log("\n");

    return Buffer.concat([encodedMethod, encodedParams]);
}


/// return this abi encoded: (address, address[], uint256[], bytes[])
function abiEncodeCalldata(calldata: TemporalGovCalldata): string {
    /// TODO encode items one by one here to compare to solidity output
    
    const encodedData = abi.rawEncode(
        ['address', 'address[]', 'uint256[]', 'bytes[]'],
        [
            calldata.temporalGovernorAddress,
            calldata.targets,
            calldata.values,
            calldata.calldata.map(data => abi.rawEncode(['bytes'], [data]))
        ]
    );
    return encodedData.toString('base64');
}

interface TemporalGovCalldata {
    targets: string[];
    calldata: Buffer[]; /// abi encoded calldata stored as a buffer
    values: number[]; /// max number is 2^53 - 1, which is safe as value is always 0. if non zero, throw error, and max number is 0.00900719925 ether
    temporalGovernorAddress: string;
}

function isNumerical(arg: string): boolean {
    const numericalPattern = /^[0-9]*\.?[0-9]+(e[0-9]+)?$/;
    return numericalPattern.test(arg);
}

function base64ToHex(base64String: string): string {
    const rawBytes = Buffer.from(base64String, 'base64');
    return rawBytes.toString('hex');
}

function buildTemporalGovCalldata(): string {
    let calldata: TemporalGovCalldata = { targets: [], calldata: [], values: [], temporalGovernorAddress: addressMap['TEMPORAL_GOVERNOR'] };

    jsonData.commands.forEach(command => { /// here error
        const target = replaceVariablesWithAddress(command.target);
        const method = command.method;

        console.log();

        /// arguments are either strings or numbers
        const args = command.arguments.map((arg: string) => {
            console.log(arg);
            console.log(typeof arg);

            return isNumerical(arg) ?
                (new BigNumber(arg)).toString() : /// if number, convert to BigNumber to prevent overflow errors and then cast to string,
                /// abiEncode will take care of turning string to an actual int
                replaceVariablesWithAddress(arg); /// if string, replace address variables with actual addresses, if no replacement, just use string
        }); /// intepret arguments as strings, and replace variables with addresses

        console.log("target: ", target);
        console.log("args: ", args);

        /// expected that values is 0
        if (target === undefined) {
            throw new Error("Target address is undefined")
        }
        if (target === '0x0000000000000000000000000000000000000000') {
            throw new Error("Target address is zero")
        }
        if (method === undefined) {
            throw new Error("Method is undefined")
        }
        if (command.values !== '0') {
            throw new Error("Value not 0, eth sending not allowed")
        }
        if (args === undefined || !Array.isArray(args)) {
            throw new Error("Payload not an array")
        }

        calldata.targets.push(target);
        calldata.calldata.push(encodeAbi(method, args)); /// error here
        calldata.values.push(0);
    });

    return abiEncodeCalldata(calldata);
}

console.log(buildTemporalGovCalldata()); /// error
console.log(`proposal bytes: ${base64ToHex(buildTemporalGovCalldata())}`);
