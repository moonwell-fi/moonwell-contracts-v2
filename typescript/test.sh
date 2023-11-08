echo "MIP02"
echo ""
PROPOSAL=./../proposals/MIP02.json npx ts-node buildCalldata.ts
cd ..
forge script src/proposals/mips/mip-b02/mip-b02.sol:mipb02 --rpc-url base -vvvvv
cd typescript

echo "MIP05"
echo ""

PROPOSAL=./../proposals/MIP05.json npx ts-node buildCalldata.ts
cd ..
forge script src/proposals/mips/mip-b05/mip-b05.sol:mipb05 --rpc-url base -vvvvv
cd typescript

echo "MIP06"
echo ""

PROPOSAL=./../proposals/MIP06.json npx ts-node buildCalldata.ts
cd ..
forge script src/proposals/mips/mip-b06/mip-b06.sol:mipb06 --rpc-url base -vvvvv

