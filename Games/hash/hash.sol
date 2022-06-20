// SPDX-License-Identifier: MIT
// An example of a consumer contract that relies on a subscription for funding.
pragma solidity 0.8.9;

import "../../lib/reentrancyguard.sol";
import "../../lib/manager.sol";

contract Hash is ReentrancyGuard, Manager {
    uint40[] public odds = [
        160,
        160,
        160,
        160,
        160,
        160,
        160,
        160,
        160,
        160,
        160,
        160,
        160,
        160,
        160,
        160,
        20,
        20,
        20,
        20,
        16,
        16,
        21
    ];
    uint40 public oddsUnit = 10;

    struct Bet {
        uint40 choice;
        uint256[] betAmount;
        uint168 placeBlockNumber;
        uint128 amount;
        uint128 winAmount;
        address player;
        bool isSettled;
        string tokenString;
        uint32 agentID;
        string transactionHash;
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
        uint256 lastNum,
        uint256 lastCharacter,
        string tokenString,
        uint32 agentID,
        address houseAddress
    );

    /** @param choice number bet choice, eg: "0101010000000000000001" means player choose bet 1 odd small, numChoice will be 25;
     * @param betAmount uint array, every dice number's bet amount and odd/even small/big bet amount, eg: [0,40000000000000000,0,50000000000000000,0,10000000000000000,20000000000000000,0,0,30000000000000000];
     * @param agentID which agent player belongs;
     * @param tokenString bet token, eg: "MATIC" or "USDT";
     */
    function placeBet(
        uint256 choice,
        uint256[] memory betAmount,
        uint32 agentID,
        string memory tokenString
    ) external payable nonReentrant {
        require(gameIsLive, "Game is not live");
        require(choice > 0, "Must bet one place");
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
                    "hash",
                    i
                );
                require(
                    betAmount[i] >= minBetAmount &&
                        betAmount[i] <= maxBetAmount,
                    "Bet amount not in range"
                );
                totalBetAmount += betAmount[i];
                totalWinnableAmount += (betAmount[i] * odds[i]) / oddsUnit;
            }
        }

        uint256 amount = totalBetAmount;

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
        uint256 betId = bets.length;
        emit BetPlaced(betId, msg.sender, amount, choice, tokenString, agentID);
        bets.push(
            Bet({
                choice: uint40(choice),
                betAmount: betAmount,
                placeBlockNumber: uint168(block.number),
                amount: uint128(amount),
                winAmount: 0,
                player: msg.sender,
                isSettled: false,
                tokenString: tokenString,
                agentID: agentID,
                transactionHash: "",
                tokenLTReward: 0
            })
        );
    }

    function settleBet(
        uint8 lastNum,
        uint8 lastCharacter,
        uint8 lastSecondCharacter,
        uint256 betId
    ) external admin {
        Bet storage bet = bets[betId];

        if (bet.amount == 0 || bet.isSettled == true) {
            return;
        }

        bet.isSettled = true;
        uint128 charge = 0;
        (bet.winAmount, charge) = calc(
            lastNum,
            lastCharacter,
            lastSecondCharacter,
            bet.choice,
            bet.betAmount,
            bet.agentID
        );

        bet.tokenLTReward = agent.calcLTCount(
            bet.agentID,
            bet.amount,
            bet.tokenString,
            "hash"
        );

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
            betId,
            bet.player,
            bet.amount,
            bet.choice,
            lastNum,
            lastCharacter,
            bet.tokenString,
            bet.agentID,
            houseAddress
        );
    }

    function calc(
        uint8 lastNum,
        uint8 lastChar,
        uint8 lastSecondChar,
        uint40 choice,
        uint256[] memory betAmount,
        uint32 agentID
    ) private view returns (uint128, uint128) {
        uint256 oddEvenOutcome;
        uint256 smallBigOutcome;
        uint256 numOutcome;
        uint256 lastTwoOutcome;
        uint256 totalWinAmount;
        uint256 winAmount;
        uint256 charge;
        uint256 chargeRate = agent.chargeRate(agentID);

        if ((choice & (1 << lastChar)) > 0) {
            totalWinAmount = betAmount[lastChar] * 15;
            charge += (totalWinAmount * chargeRate) / 10000;
            winAmount += (betAmount[lastChar] + totalWinAmount - charge);
        }

        // odd even
        if (lastNum % 2 == 0) {
            oddEvenOutcome = 20;
        } else {
            oddEvenOutcome = 21;
        }
        if ((choice & (1 << oddEvenOutcome)) > 0) {
            totalWinAmount = betAmount[oddEvenOutcome];
            charge += (totalWinAmount * chargeRate) / 10000;
            winAmount += (betAmount[oddEvenOutcome] + totalWinAmount - charge);
        }

        // small big
        if (lastNum >= 0 && lastNum <= 4) {
            smallBigOutcome = 19;
        } else {
            smallBigOutcome = 18;
        }
        if ((choice & (1 << smallBigOutcome)) > 0) {
            totalWinAmount = betAmount[smallBigOutcome];
            charge += (totalWinAmount * chargeRate) / 10000;
            winAmount += (betAmount[smallBigOutcome] + totalWinAmount - charge);
        }

        // 0-9 or a-f
        if (lastChar >= 0 && lastChar <= 9) {
            numOutcome = 17;
        } else {
            numOutcome = 16;
        }
        if ((choice & (1 << numOutcome)) > 0) {
            totalWinAmount = (betAmount[numOutcome] * 16) / 10;
            charge += (totalWinAmount * chargeRate) / 10000;
            winAmount += (betAmount[numOutcome] + totalWinAmount - charge);
        }

        // lastTwo
        if (!(
            (lastChar <= 9 &&
                lastSecondChar <= 9) ||
            (lastChar > 9 &&
                lastSecondChar > 9)
        )) {
            lastTwoOutcome = 22;
        }
        if ((choice & (1 << lastTwoOutcome)) > 0) {
            totalWinAmount = (betAmount[lastTwoOutcome] * 21) / 10;
            charge += (totalWinAmount * chargeRate) / 10000;
            winAmount += (betAmount[lastTwoOutcome] + totalWinAmount - charge);
        }
        return (uint128(winAmount), uint128(charge));
    }
}
