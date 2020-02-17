pragma solidity ^0.5.12;

import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Pausable.sol";

contract BankrollToken is Ownable, ERC20Detailed, ERC20Pausable {

    /// Token details
    string public constant NAME = "EthFrog Coin";
    string public constant SYMBOL = "FROG";
    uint8 public constant DECIMALS = 18;

    /// to easy keep tracking of burns
    uint256 public tokensBurned;

    /**
     * @dev Mints a specific amount of tokens.
     * @param _to The amount of token to be minted.
     * @param _value The amount of token to be minted.
     */
    function mint(address _to, uint256 _value) external onlyOwner {
        _mint(_to, _value);
    }

    /**
     * @dev Burns a specific amount of tokens.
     * @param _value The amount of token to be burned.
     */
    function burn(address _from, uint256 _value) external onlyOwner {
        _burn(_from, _value);
        tokensBurned = tokensBurned.add(_value);
    }

    /**
     * Initializer function.
     */
    function initialize(address _sender) public initializer {
        Ownable.initialize(_sender);

        ERC20Pausable.initialize(_sender);
        ERC20Detailed.initialize(NAME, SYMBOL, DECIMALS);
    }
}
