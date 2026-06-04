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

# Marketplace tests use *Test suffixes (not *UnitTest), so the standard
# UnitTest match-contract filter excludes them. These targets explicitly
# match the marketplace test paths.
test-marketplace:
	time forge test --match-path 'test/unit/marketplace/*' -vvv

test-marketplace-integration:
	time forge test --match-path 'test/integration/marketplace/*' --fork-url base -vvv

# Verify the numbers in a rewards-distribution MIP balance across chains.
# Usage:
#   make audit-rewards PROPOSAL=mip-x51
#   make audit-rewards                   # auto-detect from git diff main
audit-rewards:
	@./script/rewards/check-rewards-math.sh $(PROPOSAL)

# Pin in-development proposal descriptions to IPFS (Pinata) and record the
# ipfs://<cid> in the matching mips.json entry. Requires PINATA_JWT.
# Usage:
#   PINATA_JWT=... make pin-descriptions FILES="proposals/mips/mip-e00/MIP-E00.md"
#   PINATA_JWT=... make pin-descriptions   # auto-detect from git diff main
#   PIN_DRY_RUN=1 make pin-descriptions FILES=...   # no network, fake CID
pin-descriptions:
	@./script/proposals/pin-descriptions.sh $(FILES)

