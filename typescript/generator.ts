import * as fs from "fs";
import * as path from "path";
import { BigNumber } from "ethers";
import yargs from "yargs";

export type Proposal = {
  updates: ParameterUpdate[];
  description: string;
};

export type ParameterUpdate = {
  // Asset name from Addresses.json
  asset: string;
} & Partial<CollateralFactorUpdate> &
  Partial<InterestRateModelUpdate>;

type CollateralFactorUpdate = {
  // String of a decimal value from 0 to 1
  collateralFactor: string;
};

type InterestRateModelUpdate = {
  interestRateModel: {
    // Address of deployed and verified model
    address: string;

    // Params for the model to be used for verification
    // Values are expected to be decimals and will be scaled by 1e18
    params: {
      baseRatePerYear: string;
      multiplierPerYear: string;
      jumpMultiplierPerYear: string;
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

function generateParameterUpdateMip(
  // e.g. MIP-b13
  name: string,
  proposal: Proposal
): Files {
  const description = proposal.description;

  return {
    [`proposals/mips/${name}/${name}.md`]: description,
  };
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
      (argv) => {
        const name = argv.mip;

        let proposal: Proposal;

        if (argv.parameters.endsWith(".json")) {
          proposal = JSON.parse(
            fs.readFileSync(argv.parameters, "utf8")
          ) as Proposal;
        } else {
          proposal = JSON.parse(argv.parameters) as Proposal;
        }

        const files = generateParameterUpdateMip(name, proposal);

        if (!argv.dry) {
          createFiles("src", files);
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
