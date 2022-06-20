// SPDX-License-Identifier: MIT
// An example of a consumer contract that relies on a subscription for funding.
pragma solidity 0.8.9;
import "../../lib/manager.sol";

contract CoinflipBase is Manager {
    uint256 public maxCoinsBettable = 5;

    struct Bet {
        uint8 coins;
        uint40 choice;
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
        uint256 indexed coins,
        uint256 choice,
        string tokenString,
        uint32 agentID
    );
    event BetSettled(
        uint256 indexed betId,
        address indexed player,
        uint256 amount,
        uint256 indexed coins,
        uint256 choice,
        uint256 outcome,
        uint256 winAmount,
        string tokenString,
        uint32 agentID,
        uint256 randomNumber,
        address houseAddress,
        uint128 tokenLTReward
    );

    // Setter

    function setMaxCoinsBettable(uint256 _maxCoinsBettable) external admin {
        maxCoinsBettable = _maxCoinsBettable;
    }

    function calcWinAmountAndCharge(
        uint256 amount,
        uint8 coins,
        uint32 agentID
    ) internal view returns (uint128, uint128) {
        uint16 chargeRate = agent.chargeRate(agentID);
        uint128 totalWinAmount = uint128(amount * 2**coins - amount);
        uint128 charge = uint128((totalWinAmount * chargeRate) / 10000);
        return (uint128(amount + totalWinAmount - charge), uint128(charge));
    }

    function placeBetBase(
        uint256 betChoice,
        uint8 coins,
        uint32 agentID,
        string memory tokenString,
        uint256 amount
    ) public payable returns (uint256) {
        require(gameIsLive, "Game is not live");
        require(
            coins > 0 && coins <= maxCoinsBettable,
            "Coins not within range"
        );
        require(
            betChoice >= 0 && betChoice < 2**coins,
            "Bet mask not in range"
        );
        require(!Address.isContract(msg.sender), "Contract not allowed");

        IERC20 tokenAddress = agent.getTokenAddress(tokenString);
        amount = address(tokenAddress) == address(0) ? msg.value : amount;
        (uint256 minBetAmount, uint256 maxBetAmount) = agent.getLimits(
            agentID,
            address(tokenAddress),
            "coinflip",
            coins - 1
        );
        require(
            amount >= minBetAmount && amount <= maxBetAmount,
            "Bet amount not within range"
        );

        if (address(tokenAddress) == address(0)) {
            require(
                msg.sender.balance >= amount,
                "Your balance not enough"
            );
            house.checkValidate{value: msg.value}(
                amount * 2**coins,
                tokenAddress
            );
        } else {
            require(
                tokenAddress.balanceOf(msg.sender) >= amount,
                "Your token balance not enough"
            );
            SafeERC20.safeTransferFrom(tokenAddress, msg.sender, houseAddress, amount);
            house.checkValidate(amount * 2**coins, tokenAddress);
        }
        uint256 betId = bets.length;

        emit BetPlaced(
            betId,
            msg.sender,
            amount,
            coins,
            betChoice,
            tokenString,
            agentID
        );

        bets.push(
            Bet({
                coins: uint8(coins),
                choice: uint40(betChoice),
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

        return betId;

    }

    function settleBet(uint256 betId , uint256 randomNumber)
        internal
        virtual
    {
        Bet storage bet = bets[betId];

        if (bet.amount == 0 || bet.isSettled == true) {
            return;
        }

        bet.outcome = uint40(randomNumber % (2**bet.coins));

        uint128 charge = 0;
        if (bet.choice == bet.outcome) {
            (bet.winAmount, charge) = calcWinAmountAndCharge(
                bet.amount,
                bet.coins,
                bet.agentID
            );
        }

        bet.isSettled = true;
        bet.randomNumber = randomNumber;

        bet.tokenLTReward = agent.calcLTCount(bet.agentID, bet.amount, bet.tokenString, "coinflip");
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
            bet.coins,
            bet.choice,
            bet.outcome,
            bet.winAmount,
            bet.tokenString,
            bet.agentID,
            bet.randomNumber,
            houseAddress,
            bet.tokenLTReward
        );
    }
}
