//SPDX-License-Identifier: UNLICENSED

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@thetrees1529/solutils/contracts/payments/Fees.sol";
import "@thetrees1529/solutils/contracts/payments/Payments.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/*
    Keyhashes
        AVAX: 0x354d2f95da55398f44b7cff77da56283d9c6c829a4bdf1bbcaf2ad6a4d081f61

*/

pragma solidity 0.8.16;

contract Dice is VRFConsumerBaseV2, Payments, Ownable {

    using Fees for uint;

    struct OddsInput {
        uint chance;
        uint outOf;
    }

    struct Odds {
        uint chance;
        uint outOf;
    }

    struct Game {
        address from;
        Odds odds;
        uint bet;
        bool rolled;
        uint roll;
        uint won;
    }

    bytes32 private _keyHash;
    uint64 private _subId;
    uint16 private _minimumRequestConfirmations = 3;
    uint32 private _callbackGasLimit = 2500000;
    uint32 private _numWords = 1;

    VRFCoordinatorV2Interface private _vrfCoordinator;
    Fees.Fee public fee;
    mapping(uint => uint) private _ids;
    mapping(address => uint[]) public involvedIn;
    Game[] public games;

    constructor(address vrfCoordinator, Payments.Payee[] memory payees, Fees.Fee memory fee_, bytes32 keyHash, uint64 subId) VRFConsumerBaseV2(vrfCoordinator) Payments(payees) {
        fee = fee_;
        _vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        (_keyHash, _subId) = (keyHash, subId);
    }

    function rollDie(OddsInput calldata oddsInput) external payable {
        Odds memory odds = _getOdds(oddsInput);
        uint id = games.length;
        Game storage game = games.push();
        game.from = msg.sender;
        game.odds = odds;
        game.bet = msg.value;
        uint rId = _vrfCoordinator.requestRandomWords(_keyHash, _subId, _minimumRequestConfirmations, _callbackGasLimit, _numWords);
        _ids[rId] = id;
        involvedIn[msg.sender].push(id);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal virtual override {
        Game storage game = games[_ids[requestId]];
        Odds storage odds = game.odds;
        require(!game.rolled);
        uint randomNumber = randomWords[0];
        uint roll = randomNumber % odds.outOf;
        bool won = roll < odds.outOf;
        if(won) {
            uint winningsBeforeFees = (game.bet * odds.outOf) / odds.chance;
            uint toDevs = winningsBeforeFees.feesOf(fee);
            uint winnings = winningsBeforeFees - toDevs;
            sendTx(game.from, winnings);
            _makePayment(toDevs);
            game.won = winnings;
        } else {
            _makePayment(game.bet);
        }
        game.rolled = true;
        game.roll = roll;
    }

    function refund(uint256 gameId) external onlyOwner {
        Game storage game = games[gameId];
        require(!game.rolled);
        game.rolled = true;
        sendTx(game.from, game.bet);
    }

    function _getOdds(OddsInput memory oddsInput) private pure returns(Odds memory) {
        require(oddsInput.chance > 0 && oddsInput.outOf > oddsInput.chance, "Bad odds.");
        return Odds(oddsInput.chance, oddsInput.outOf);
    }

    function sendTx(address to, uint value) private {
        (bool success,) = to.call{value: value}("");
        require(success);
    }

    function deposit() external payable onlyOwner {}
    function withdraw(uint value) external onlyOwner {
        (bool success,) = msg.sender.call{value: value}("");
        require(success);
    }

}