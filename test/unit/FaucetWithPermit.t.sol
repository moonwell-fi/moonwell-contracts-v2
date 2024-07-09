pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {FaucetTokenWithPermit} from "@test/helper/FaucetToken.sol";
import {SigUtils} from "@test/helper/SigUtils.sol";

contract FaucetWithPermitUnitTest is Test {
    FaucetTokenWithPermit token;
    SigUtils sigUtils;
    uint256 ownerPrivateKey;
    uint256 spenderPrivateKey;
    address owner;
    address spender;

    function setUp() public {
        token = new FaucetTokenWithPermit(1e18, "Testing", 18, "TEST");
        sigUtils = new SigUtils(token.DOMAIN_SEPARATOR());

        ownerPrivateKey = 0xA11CE;
        spenderPrivateKey = 0xB0B;

        owner = vm.addr(ownerPrivateKey);
        spender = vm.addr(spenderPrivateKey);

        token.allocateTo(owner, 1e18);
    }

    function testPermit() public {
        assertEq(token.balanceOf(owner), 1e18);

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: 1e18,
            nonce: 0,
            deadline: 1 minutes
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(
            permit.owner, permit.spender, permit.value, permit.deadline, v, r, s
        );

        assertEq(token.allowance(owner, spender), 1e18);
        assertEq(token.nonces(owner), 1);
    }
}
