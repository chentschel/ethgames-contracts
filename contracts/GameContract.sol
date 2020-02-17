pragma solidity ^0.5.12;

import "./Bankroll.sol";
import "./StateChannel.sol";
import "../node_modules/openzeppelin-eth/contracts/ownership/Ownable.sol";


contract GameContract is Ownable, Bankroll, StateChannel {

    /**
     * @dev The House constructor sets the original `owner` of the contract to the sender
     * account and initializes the houseToken
     * @param sender of the initialize call
     */
    function initialize(address sender) external initializer {
        Ownable.initialize(sender);

        Bankroll.initialize(sender);
        StateChannel.initialize(sender);
    }

}