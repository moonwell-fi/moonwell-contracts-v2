import * as fs from "fs";
import * as path from "path";
import { BigNumber } from "ethers";
import yargs from "yargs";
import { generateMipScript } from "./mipScript";

export type Proposal = {
  updates: ParameterUpdate[];
  description: string;
};

export type ParameterUpdate = {
  // Asset name from Addresses.json
  asset: string;
} & Partial<CollateralFactorUpdate> &
  Partial<InterestRateModelUpdate>;

export type CollateralFactorUpdate = {
  asset: string;
  // String of a decimal value from 0 to 1
  collateralFactor: string;
};

export type InterestRateModelUpdate = {
  asset: string;
  interestRateModel: {
    // Address of deployed and verified model
    address: string;

    // Params for the model to be used for verification
    // Values are expected to be decimals and will be scaled by 1e18
    params: {
      baseRatePerTimestamp: string;
      multiplierPerTimestamp: string;
      jumpMultiplierPerTimestamp: string;
      kink: string;
    };
  };
};

interface Files {
  [name: string]: string;
}

function createFiles(folderPath: string, files: Files): void {
  Object.keys(files).forEach((name) => {
    fs.mkdirSync(path.dirname(path.join(folderPath, name)), {
      recursive: true,
    });
    fs.writeFileSync(path.join(folderPath, name), files[name]);
  });
}

async function generateParameterUpdateMip(
  // e.g. MIP-b13
  name: string,
  proposal: Proposal
): Promise<Files> {
  const description = proposal.description;

  const script = await generateMipScript(name, proposal);

  return {
    [`proposals/mips/${name}/${name}.md`]: description,
    [`proposals/mips/${name}/${name}.sol`]: script,
  };
}

type AddressEntry = {
  addr: string;
  chainId: number;
  name: string;
};

function performAddressesUpdates(proposal: Proposal): void {
  const rateUpdates = proposal.updates.filter(
    (update) => "interestRateModel" in update
  ) as InterestRateModelUpdate[];

  const addressesPath = path.join("utils", "Addresses.json");
  const addresses: AddressEntry[] = JSON.parse(
    fs.readFileSync(addressesPath, "utf8")
  );

  const baseChainId = 8453;

  rateUpdates.forEach((update) => {
    for (const address of addresses) {
      if (address.chainId === baseChainId) {
        if (address.name === `JUMP_RATE_IRM_MOONWELL_${update.asset}`) {
          address.addr = update.interestRateModel.address;
        }
      }
    }
  });

  // Write back edited JSON
  fs.writeFileSync(addressesPath, JSON.stringify(addresses, null, 4));
}

async function main(): Promise<void> {
  await yargs
    .command(
      "generate",
      "Generate new parameter update MIP",
      (yargs) => {
        return yargs
          .option("mip", {
            type: "string",
            description: "MIP name to generate",
            demandOption: true,
          })
          .option("parameters", {
            type: "string",
            description:
              "Path to JSON file with Proposal OR a direct JSON string.",
            demandOption: true,
          })
          .option("dry", {
            type: "boolean",
            description: "Dry run, don't generate files",
            default: false,
          });
      },
      async (argv) => {
        const name = argv.mip;

        let proposal: Proposal;

        if (argv.parameters.endsWith(".json")) {
          proposal = JSON.parse(
            fs.readFileSync(argv.parameters, "utf8")
          ) as Proposal;
        } else {
          proposal = JSON.parse(argv.parameters) as Proposal;
        }

        const files = await generateParameterUpdateMip(name, proposal);

        if (!argv.dry) {
          createFiles("src", files);

          performAddressesUpdates(proposal);
        }
      }
    )
    .demandCommand(1, "You need at least one command before moving on")
    .help()
    .parseAsync();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
