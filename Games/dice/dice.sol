// SPDX-License-Identifier: MIT
// An example of a consumer contract that relies on a subscription for funding.
pragma solidity 0.8.9;

import "../../lib/reentrancyguard.sol";
import "../../lib/random.sol";
import "../../lib/manager.sol";

contract Dice is ReentrancyGuard, Random, Manager {
    uint256 public constant MOD = 6;

    uint40[] public odds = [6, 6, 6, 6, 6, 6, 2, 2, 2, 2];

    struct Bet {
        uint40 choice;
        uint256[] betAmount;
        uint40 outcome;
        uint168 placeBlockNumber;
        uint128 amount;
        uint128 winAmount;
        address player;
        bool isSettled;
        string tokenString;
        uint32 agentID;
        uint256 randomNumber;
        uint128 tokenLTReward;
    }

    Bet[] public bets;

    function betsLength() external view returns (uint256) {
        return bets.length;
    }

    // Events
    event BetPlaced(
        uint256 indexed betId,
        address indexed player,
        uint256 amount,
        uint256 choice,
        string tokenString,
        uint32 agentID
    );
    event BetSettled(
        uint256 indexed betId,
        address indexed player,
        uint256 amount,
        uint256 choice,
        uint256 outcome,
        uint256 winAmount,
        string tokenString,
        uint32 agentID,
        uint256 randomNumber,
        address houseAddress
    );



    /** @param numChoice dice number bet choice, eg: "0101011001" means player choose bet 1/4/5 odd small, numChoice will be 25;
     * @param betAmount uint array, every dice number's bet amount and odd/even small/big bet amount, eg: [0,40000000000000000,0,50000000000000000,0,10000000000000000,20000000000000000,0,0,30000000000000000];
     * @param agentID which agent player belongs;
     * @param tokenString bet token, eg: "MATIC" or "USDT";
     */
    function placeBet(
        uint256 numChoice,
        uint256[] memory betAmount,
        uint32 agentID,
        string memory tokenString
    ) external payable nonReentrant {
        require(gameIsLive, "Game is not live");
        require(isEnoughLinkForBet(), "Insufficient LINK token");
        require(numChoice > 0, "Must bet one place");
        uint256 totalBetAmount = 0;
        uint256 totalWinnableAmount = 0;
        IERC20 tokenAddress = agent.getTokenAddress(tokenString);
        for (uint8 i = 0; i < betAmount.length; i++) {
            if (betAmount[i] > 0) {
                uint256 minBetAmount = 0;
                uint256 maxBetAmount = 0;
                (minBetAmount, maxBetAmount) = agent.getLimits(
                    agentID,
                    address(tokenAddress),
                    "dice",
                    i
                );
                require(
                    betAmount[i] >= minBetAmount &&
                        betAmount[i] <= maxBetAmount,
                    "Bet amount not in range"
                );
                totalBetAmount += betAmount[i];
                totalWinnableAmount += betAmount[i] * odds[i];
            }
        }

        uint256 amount = totalBetAmount;

        uint256 betId = bets.length;
        IERC20 token = agent.getTokenAddress(tokenString);

        if (address(token) == address(0)) {
            require(msg.value >= amount, "bet amount not enough");
            house.checkValidate{value: msg.value}(totalWinnableAmount, token);
        } else {
            require(
                token.balanceOf(msg.sender) >= amount,
                "Your token balance not enough"
            );
            SafeERC20.safeTransferFrom(token, msg.sender, houseAddress, amount);
            house.checkValidate(totalWinnableAmount, token);
        }

        bytes32 requestId = requestRandomness(keyHash, chainlinkFee);
        betMap[requestId] = betId;

        emit BetPlaced(betId, msg.sender, amount, numChoice, tokenString, agentID);
        bets.push(
            Bet({
                choice: uint40(numChoice),
                betAmount: betAmount,
                outcome: 0,
                placeBlockNumber: uint168(block.number),
                amount: uint128(amount),
                winAmount: 0,
                player: msg.sender,
                isSettled: false,
                tokenString: tokenString,
                agentID: agentID,
                randomNumber: 0,
                tokenLTReward: 0
            })
        );
    }

    // Callback function called by Chainlink VRF coordinator.
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        settleBet(requestId, randomness);
    }

    // Function can only be called by fulfillRandomness function, which in turn can only be called by Chainlink VRF.
    function settleBet(bytes32 requestId, uint256 randomNumber)
        private
        nonReentrant
    {
        Bet storage bet = bets[betMap[requestId]];

        if (bet.amount == 0 || bet.isSettled == true) {
            return;
        }

        bet.outcome = uint40(randomNumber % MOD);
        bet.isSettled = true;
        bet.randomNumber = randomNumber;
        uint128 charge = 0;
        (bet.winAmount, charge) = calc(
            bet.agentID,
            bet.betAmount,
            bet.choice,
            bet.outcome
        );

        bet.tokenLTReward = agent.calcLTCount(bet.agentID, bet.amount, bet.tokenString, "dice");

        house.settleBet(
            bet.player,
            bet.winAmount,
            charge,
            bet.agentID,
            bet.tokenLTReward,
            bet.winAmount > 0,
            agent.getTokenAddress(bet.tokenString)
        );

        emit BetSettled(
            betMap[requestId],
            bet.player,
            bet.amount,
            bet.choice,
            bet.outcome,
            bet.winAmount,
            bet.tokenString,
            bet.agentID,
            bet.randomNumber,
            houseAddress
        );
    }

    function calc(
        uint32 agentID,
        uint256[] memory betAmount,
        uint256 choice,
        uint256 outcome
    ) private view returns (uint128, uint128) {
        uint256 winAmount = 0;
        uint256 charge = 0;
        uint256 chargeRate = agent.chargeRate(agentID);
        if ((choice & (1 << outcome)) > 0) {
            winAmount =
                (betAmount[outcome] * MOD * (10000 - chargeRate)) /
                10000;
            charge += (betAmount[outcome] * MOD * chargeRate) / 10000;
        }

        uint256 oddEvenOutcome;
        if ((outcome + 1) % 2 == 0) {
            oddEvenOutcome = 7;
        } else {
            oddEvenOutcome = 6;
        }

        if ((choice & (1 << oddEvenOutcome)) > 0) {
            winAmount +=
                (betAmount[oddEvenOutcome] *
                    odds[oddEvenOutcome] *
                    (10000 - chargeRate)) /
                10000;
            charge +=
                (betAmount[oddEvenOutcome] *
                    odds[oddEvenOutcome] *
                    chargeRate) /
                10000;
        }

        uint256 smallBigOutcome;
        if (outcome >= 0 && outcome <= 2) {
            smallBigOutcome = 8;
        } else {
            smallBigOutcome = 9;
        }
        if ((choice & (1 << oddEvenOutcome)) > 0) {
            winAmount +=
                (betAmount[smallBigOutcome] *
                    odds[smallBigOutcome] *
                    (10000 - chargeRate)) /
                10000;
            charge +=
                (betAmount[smallBigOutcome] *
                    odds[smallBigOutcome] *
                    chargeRate) /
                10000;
        }

        return (uint128(winAmount), uint128(charge));
    }
}
