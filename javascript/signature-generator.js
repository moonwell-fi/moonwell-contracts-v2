global.window = {}

const Web3 = require('./web3.min.js')
const fs = require('fs')
const path = require('path')

let web3 = new Web3('https://base.meowrpc.com')

const parseArtifacts = async () => {
  const signatures = {}
  const contracts = fs.readdirSync(path.resolve('../artifacts/foundry/'))
  for (const contractFolder of contracts) {
    const contractJson = fs.readdirSync(
      path.join(path.resolve('../artifacts/foundry/'), contractFolder)
    )
    for (const contract of contractJson) {
      if (contract.indexOf('.json') >= 0 && contractFolder.indexOf('.t.') == -1) {
        const json = fs.readFileSync(
          path.join(
            path.resolve('../artifacts/foundry/'),
            contractFolder,
            contract
          )
        )
        const jsonObject = JSON.parse(json.toString())
        if (jsonObject.abi) {
          let functions = jsonObject.abi.filter(r => r.type == 'function')
          for (const func of functions) {
            let signatureRaw = `${func.name}(${func.inputs
              .map(i => `${i.type}`)
              .join(',')})`
            let signature = `${func.name}(${func.inputs
              .map(i => `${i.type} ${i.name}`)
              .join(',')})`

            let encoded_signature =
              web3.eth.abi.encodeFunctionSignature(signatureRaw)

            signatures[encoded_signature.substring(2)] = {
              signature,
              name: func.name,
              inputs: func.inputs.map(i => `${i.type} ${i.name}`),
              contract: contract.replace('.json', '')
            }
          }
        }
      }
    }
  }

  fs.writeFileSync(
    path.resolve('../other/signatures.json'),
    JSON.stringify(signatures, null, '\t')
  )
}

parseArtifacts()
