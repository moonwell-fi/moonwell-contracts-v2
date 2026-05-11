TAG = moonwell-contracts

build-docker:
	docker build -t $(TAG) .

# npx hardhat run --network base-localhost scripts/deploy-testnet.ts

moonbeam-node:
	docker run --rm -it -p 8545:8545 $(TAG) ganache-cli \
	    -h 0.0.0.0 \
	    --fork.url https://rpc.api.moonbeam.network \
	    --fork.blockNumber 3302234 \
	    --chain.chainId 1284 \
	    -u 0xFFA353daCD27071217EA80D3149C9d500B0e9a38 \
	    -b 1

bash:
	docker run --rm -it \
		-v $$(pwd):$$(pwd) \
		--workdir $$(pwd) \
		--net=host \
		$(TAG) \
		bash

base-testnet:
	docker run --rm -it \
		-v $$(pwd):$$(pwd) \
		--workdir $$(pwd) \
		-p 8545:8545 \
		$(TAG) \
		ganache-cli --fork https://goerli.base.org/ --host 0.0.0.0 --chain.chainId 84531 --wallet.deterministic

base:
	docker run --rm -it \
		-v $$(pwd):$$(pwd) \
		--workdir $$(pwd) \
		-p 8545:8545 \
		$(TAG) \
		ganache-cli --fork https://developer-access-mainnet.base.org --host 0.0.0.0 --chain.chainId 8453 --wallet.deterministic

# Anvil unfortunately doesn't work for deploys due to a bug in their gas estimation - https://github.com/foundry-rs/foundry/pull/2294
# anvil -f https://goerli.base.org/ --host 0.0.0.0

slither:
    docker run --rm -it \
		-v $$(pwd):$$(pwd) \
		--workdir $$(pwd) \
		$(TAG) \
        slither --solc-remaps '@openzeppelin/contracts/=node_modules/@openzeppelin/contracts/' .

# Proxy requests to the local node, useful for debugging opaque failures
mitmproxy:
    docker run --rm -it --net=host mitmproxy/mitmproxy mitmproxy --mode reverse:http://host.docker.internal:8545@8081

coverage:
	time forge coverage --skip script \
        --out artifacts/coverage \
        --skip "Integration.t.sol" \
		--summary --report lcov \
        --match-contract UnitTest

test-unit:
	time forge test --match-contract UnitTest -vvv

# Verify the numbers in a rewards-distribution MIP balance across chains.
# Usage:
#   make audit-rewards PROPOSAL=mip-x51
#   make audit-rewards                   # auto-detect from git diff main
audit-rewards:
	@./script/rewards/check-rewards-math.sh $(PROPOSAL)

# Migration harness: full mip-x56 + mip-e00 end-to-end run against persistent
# Tenderly VNets. The VNet bootstrap lives in
# ../defender-migration/moonwell-tenderly and writes per-chain RPC URLs to
# .env.migration-vnets using the same env-var names foundry.toml's
# [rpc_endpoints] block already references.
TENDERLY_DIR ?= ../defender-migration/moonwell-tenderly

migration-vnets-up:
	cd $(TENDERLY_DIR) && bun run setup-migration-vnets

migration-vnets-down:
	cd $(TENDERLY_DIR) && bun run setup-migration-vnets -- --teardown

migration-harness: migration-vnets-up
	set -a; \
	  . $(TENDERLY_DIR)/.env.migration-vnets; \
	  set +a; \
	  forge test --mc MigrationHarness --ffi -vv; \
	  status=$$?; \
	  $(MAKE) migration-vnets-down; \
	  exit $$status

migration-harness-keep: migration-vnets-up
	set -a; \
	  . $(TENDERLY_DIR)/.env.migration-vnets; \
	  set +a; \
	  forge test --mc MigrationHarness --ffi -vv

