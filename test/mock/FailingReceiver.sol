pragma solidity 0.8.19;

contract FailingReceiver {

    fallback() external payable {
        revert("FailingReceiver: fallback reverted");
    }
}
