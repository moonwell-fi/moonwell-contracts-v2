forge test --match-contract UnitTest -vvv 
forge test --match-contract IntegrationTest --fork-url ethereum -vvv
forge test --match-contract ArbitrumTest --fork-url arbitrum -vvv
forge test --match-contract MoonbeamTest --fork-url moonbeam -vvv
forge test --match-contract LiveSystemTest --fork-url baseSepolia -vvv
forge test --match-contract LiveSystemBaseTest --fork-url base -vvv
forge test --match-contract CrossChainPublishMessageTest -vvv 
forge test --match-contract MultichainProposalTest -vvv
