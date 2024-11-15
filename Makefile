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

