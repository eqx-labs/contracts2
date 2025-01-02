// this smart contract registers gateway IP addresses
// operators can only communicate with whitelisted IP addresses here

pragma solidity ^0.8.0;

contract GatewayRegistry {
    address public owner;
    string[] private gatewayIPs;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function addGatewayIP(string memory ip) public onlyOwner {
        gatewayIPs.push(ip);
    }

    function removeGatewayIPByValue(string memory ip) public onlyOwner {
        for (uint i = 0; i < gatewayIPs.length; i++) {
            if (keccak256(abi.encodePacked(gatewayIPs[i])) == keccak256(abi.encodePacked(ip))) {
                gatewayIPs[i] = gatewayIPs[gatewayIPs.length - 1];
                gatewayIPs.pop();
            }
        }
    }

    function getGatewayIPs() public view returns (string[] memory) {
        return gatewayIPs;
    }
}