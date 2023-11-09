echo "------------- MIP02 -------------"
echo ""
PROPOSAL=./proposals/MIPB02.json npx ts-node typescript/buildCalldata.ts
echo "\n\n\n"
forge script src/proposals/mips/mip-b02/mip-b02.sol:mipb02 --rpc-url base -vvvvv

echo "------------- MIP05 -------------"
echo "\n\n\n"

PROPOSAL=./proposals/MIPB05.json npx ts-node typescript/buildCalldata.ts
echo "\n\n\n"
forge script src/proposals/mips/mip-b05/mip-b05.sol:mipb05 --rpc-url base -vvvvv

echo "------------- MIP06 -------------"
echo "\n\n\n"

PROPOSAL=./proposals/MIPB06.json npx ts-node typescript/buildCalldata.ts
echo "\n\n\n"
forge script src/proposals/mips/mip-b06/mip-b06.sol:mipb06 --rpc-url base -vvvvv

