pragma solidity ^0.8.0;

contract MockWormholeReceiver {
    uint256 public price;
    uint64 public nonce;

    function setPriceQuote(uint256 nativePriceQuote) public {
        price = nativePriceQuote;
    }

    function quoteEVMDeliveryPrice(uint16, uint256, uint256) external view returns (uint256, uint256) {
        return (price, 0);
    }

    function sendPayloadToEvm(
        uint16,
        address,
        bytes memory,
        uint256 receiverValue,
        uint256
    ) external payable returns (uint64 sequence) {
        require(receiverValue == 0, "something is wrong with unit tests");
        nonce++;
        sequence = nonce;
    }
}
