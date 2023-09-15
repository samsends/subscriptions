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
    event SubscriptionLiquidation(
        address indexed user,
        address indexed liquidator,
        uint256 reward
    );

    function depositETH() external payable {
        updateBalance(msg.sender);
        balances[msg.sender] += msg.value;
    }

    // New function for withdrawing funds
    function withdraw(uint256 amount) external {
        uint256 userOutflow = outflowRates[msg.sender];
        uint256 liquidationThreshold = userOutflow * 6000; // 2 times the original threshold
        require(
            balances[msg.sender] >= liquidationThreshold,
            "Below liquidation threshold"
        );
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
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
        uint256 newAmountPerBlock
    ) external {
        require(
            newAmountPerBlock <= balances[msg.sender],
            "Insufficient balance to update subscription"
        );

        updateBalance(msg.sender);
        updateBalance(recipient);

        uint256 oldAmountPerBlock = subscriptions[msg.sender][recipient];

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

    function cancelSubscription(address recipient) external {
        updateBalance(msg.sender);
        updateBalance(recipient);

        uint256 oldAmountPerBlock = subscriptions[msg.sender][recipient];

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
        return currentBalance >= currentRate && currentRate >= expectedRate;
    }

    function liquidateSubscriptions(
        address user,
        address[] memory recipients
    ) external {
        uint256 userBalance = balances[user]; // Single read
        uint256 userOutflow = outflowRates[user]; // Single read
        uint256 liquidationThreshold = userOutflow * 3000;

        // Check if the user's balance is below the liquidation threshold
        if (userBalance < liquidationThreshold) {
            uint256 totalCanceledOutflow = 0;

            // Cancel all subscriptions for this user
            for (uint i = 0; i < recipients.length; i++) {
                address recipient = recipients[i];
                uint256 oldAmountPerBlock = subscriptions[user][recipient];
                userOutflow -= oldAmountPerBlock; // Update in memory
                inflowRates[recipient] -= oldAmountPerBlock; // Single write per loop iteration
                subscriptions[user][recipient] = 0; // Single write per loop iteration
                totalCanceledOutflow += oldAmountPerBlock;
                emit SubscriptionCanceled(user, recipient);
            }

            // Calculate the reward for the liquidator
            uint256 remainingBlocks = userBalance / userOutflow;
            uint256 reward = totalCanceledOutflow * (remainingBlocks / 2);

            // If outflow is zero, give the liquidator all remaining user funds
            if (userOutflow == 0) {
                reward = userBalance;
            }

            // Cap the reward to the user's remaining balance
            reward = (reward > userBalance) ? userBalance : reward;

            // Update balances and outflowRates in storage (single write)
            balances[user] = userBalance - reward;
            balances[msg.sender] += reward;
            outflowRates[user] = userOutflow;

            // Emit an event to notify that the user's subscriptions have been liquidated
            emit SubscriptionLiquidation(user, msg.sender, reward);
            (user, msg.sender, reward);
        }
    }
}
