// SPDX-License-Identifier: MIT
// An example of a consumer contract that relies on a subscription for funding.
pragma solidity 0.8.9;

import "../../lib/reentrancyguard.sol";
import "../../lib/random.sol";
import "./coinflip_base.sol";

contract Coinflip is CoinflipBase, ReentrancyGuard, Random {
    function placeBet(
        uint256 betChoice,
        uint8 coins,
        uint32 agentID,
        string memory tokenString,
        uint256 amount
    ) external payable nonReentrant returns (uint256){
        require(isEnoughLinkForBet(), "Insufficient LINK token");
        uint256 betId = placeBetBase(betChoice, coins, agentID, tokenString, amount);
        bytes32 requestId = requestRandomness(keyHash, chainlinkFee);
        betMap[requestId] = betId;
        return betId;
    }

    // Callback function called by Chainlink VRF coordinator.
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        
        settleBet(betMap[requestId], randomness);
    }

    // Function can only be called by fulfillRandomness function, which in turn can only be called by Chainlink VRF.
    function settleBet(uint256 betId, uint256 randomNumber)
        internal
        nonReentrant
        override
    {
        super.settleBet(betId, randomNumber);
    }
}
