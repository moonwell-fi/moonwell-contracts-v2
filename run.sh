forge test -vvv --match-contract UnitTest
forge test --match-contract IntegrationTest --fork-url $ETH_RPC_URL -vvv
forge test --match-contract ArbitrumTest --fork-url $ARB_RPC_URL -vvv
forge test --match-contract MoonbeamTest --fork-url $MOONBEAN_RPC_URL -vvv
forge test --match-contract LiveSystemTest --fork-url baseGoerli -vvv
forge test --match-contract LiveSystemBaseTest --fork-url base -vvv
forge test -vvv --match-contract CrossChainPublishMessageTest