// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Subscription {
    mapping(address => uint256) public balances; // user => balance
    mapping(address => uint256) public outflowRates; // user => total outflow rate per block
    mapping(address => uint256) public inflowRates; // user => total inflow rate per block
    mapping(address => uint256) public lastUpdatedBlock; // user => last updated block number
    mapping(address => mapping(address => uint256)) public subscriptions; // user => recipient => outflow rate to recipient

    event SubscriptionCreated(
        address indexed user,
        address indexed recipient,
        uint256 amountPerBlock
    );
    event SubscriptionUpdated(
        address indexed user,
        address indexed recipient,
        uint256 newAmountPerBlock
    );
    event SubscriptionCanceled(address indexed user, address indexed recipient);

    function depositETH() external payable {
        updateBalance(msg.sender);
        balances[msg.sender] += msg.value;
    }

    function createSubscription(
        address recipient,
        uint256 amountPerBlock
    ) external {
        require(
            amountPerBlock <= balances[msg.sender],
            "Insufficient balance to create subscription"
        );

        updateBalance(msg.sender);
        updateBalance(recipient);

        outflowRates[msg.sender] += amountPerBlock;
        inflowRates[recipient] += amountPerBlock;
        subscriptions[msg.sender][recipient] = amountPerBlock;

        emit SubscriptionCreated(msg.sender, recipient, amountPerBlock);
    }

    function updateSubscription(
        address recipient,
        uint256 newAmountPerBlock,
        uint256 oldAmountPerBlock
    ) external {
        require(
            newAmountPerBlock <= balances[msg.sender],
            "Insufficient balance to update subscription"
        );

        updateBalance(msg.sender);
        updateBalance(recipient);

        outflowRates[msg.sender] =
            outflowRates[msg.sender] -
            oldAmountPerBlock +
            newAmountPerBlock;
        inflowRates[recipient] =
            inflowRates[recipient] -
            oldAmountPerBlock +
            newAmountPerBlock;
        subscriptions[msg.sender][recipient] = newAmountPerBlock;

        emit SubscriptionUpdated(msg.sender, recipient, newAmountPerBlock);
    }

    function cancelSubscription(
        address recipient,
        uint256 oldAmountPerBlock
    ) external {
        updateBalance(msg.sender);
        updateBalance(recipient);

        outflowRates[msg.sender] -= oldAmountPerBlock;
        inflowRates[recipient] -= oldAmountPerBlock;
        subscriptions[msg.sender][recipient] = 0;

        emit SubscriptionCanceled(msg.sender, recipient);
    }

    function updateBalance(address user) internal {
        uint256 blocksPassed = block.number - lastUpdatedBlock[user];
        uint256 inflow = inflowRates[user] * blocksPassed;
        uint256 outflow = outflowRates[user] * blocksPassed;

        require(
            balances[user] >= outflow,
            "Insufficient balance to continue subscription"
        );

        balances[user] = balances[user] + inflow - outflow;
        lastUpdatedBlock[user] = block.number;
    }

    function getBalance(address user) public view returns (uint256) {
        uint256 blocksPassed = block.number - lastUpdatedBlock[user];
        uint256 inflow = inflowRates[user] * blocksPassed;
        uint256 outflow = outflowRates[user] * blocksPassed;

        if (balances[user] < outflow) {
            return 0;
        }

        return balances[user] + inflow - outflow;
    }

    function verifySubscription(
        address user,
        address recipient,
        uint256 expectedRate
    ) external view returns (bool) {
        uint256 currentBalance = getBalance(user);
        uint256 currentRate = subscriptions[user][recipient];
        return currentBalance >= currentRate && currentRate == expectedRate;
    }
}
