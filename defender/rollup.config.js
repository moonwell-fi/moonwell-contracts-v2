const builtins = require('builtin-modules');
const commonjs = require('@rollup/plugin-commonjs');
const json = require('@rollup/plugin-json');
const nodeResolve = require('@rollup/plugin-node-resolve').nodeResolve;

export default {
    input: 'src/emitVotes.js',
    output: {
        file: 'dist/index.js',
        format: 'cjs',
    },
    plugins: [
        nodeResolve({preferBuiltins: true}),
        commonjs(),
        json({compact: true}),
    ],
    external: [
        ...builtins,
        'ethers',
        'web3',
        'axios',
        /^defender-relay-client(\/.*)?$/,
    ],
};
