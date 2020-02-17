pragma solidity ^0.5.0;

import "../node_modules/openzeppelin-eth/contracts/math/SafeMath.sol";
import "../node_modules/openzeppelin-eth/contracts/ownership/Ownable.sol";
import "./BankrollToken.sol";

contract Bankroll is Ownable {

    using SafeMath for uint256;

    event onInvest(address indexed investor, uint256 amount);
    event onDivest(address indexed investor, uint256 amount);
    event onTransferHouse(address indexed previousBeneficiary, address indexed newBeneficiary);

    // house address to send profits to
    address payable private beneficiary;

    // Tokens representing house shares
    BankrollToken public houseToken;

    // Account investments
    mapping (address => uint256) public bankrollMap;

    // Accounts for total bankroll investment in wei
    uint256 public totalInvested;

    /**
     * @dev The House constructor sets the original `owner` of the contract to the sender
     * account and initializes the houseToken
     * @param _owner of the initialize call
     */
    function initialize(address _owner) public initializer {
        Ownable.initialize(_owner);

        // Set beneficiary to contract owner
        beneficiary = _owner;

        // Create a house token and set owner to this contract
        houseToken = new BankrollToken();
        houseToken.initialize(address(this));
    }

    /**
     * @dev Transfers beneficiary address of the contract to a newBeneficiary
     * @param _beneficiary The address to transfer house profits to.
     */
    function setBeneficiaryAddress(address _beneficiary) public onlyOwner {
        require(_beneficiary != address(0), "beneficiary invalid");

        beneficiary = _beneficiary;
        emit onTransferHouse(beneficiary, _beneficiary);
    }

    /**
     * @dev Calculate current share price, don't account the
     *  current msg.value contract in balance.
     * @return share value based on house balance / shares supply
     */
    function getSharePrice() public view returns (uint256) {
        return _getSharePrice(address(this).balance);
    }

    /**
     * @dev Calculates total invested + shared profits
     */
    function currentBankroll() public view returns (int256) {
        uint256 totalBalance = address(this).balance;

        return int256(totalInvested) + (int256(totalBalance) - int256(totalInvested)) / 2;
    }

    /**
     * @dev Calculate profit in wei for given investor
     * @return investor profit in wei since last withdraw
     */
    function investorProfit() public view returns (int256) {
        uint256 investment = bankrollMap[msg.sender];
        uint256 investorShares = houseToken.balanceOf(msg.sender);

        uint256 sharePrice = getSharePrice();

        // Investor profit is calculated based on current
        // value of shares, minus accounted investment
        // and divided by 50% for house share.
        return ((int256(sharePrice) * int256(investorShares)) - int256(investment)) / 2;
    }

    /**
     * @dev Invest on bankroll.
     */
    function invest() public payable {
        require(msg.value > 0, "value should be > 0");

        // Call internal share price calculation,
        // not accounting current msg value.
        uint256 sharePrice = _getSharePrice(
            address(this).balance - msg.value
        );
        uint256 sharesAmount = msg.value.div(sharePrice);

        houseToken.mint(msg.sender, sharesAmount);

        // Track investments
        bankrollMap[msg.sender] += msg.value;

        // Global invested
        totalInvested += msg.value;

        emit onInvest(msg.sender, msg.value);
    }

    /**
     * @dev Divest from bankroll.
     * @param _amount in shares to divest
     */
    function divest(uint256 _amount) public {
        uint256 investorShares = houseToken.balanceOf(msg.sender);

        require(_amount <= investorShares, "amount > account balance");

        // Calculate share and divestment value
        uint256 sharePrice = getSharePrice();
        uint256 divestValue = _amount.mul(sharePrice);

        // Calculate tokens value of the original investment
        uint256 originalValue = bankrollMap[msg.sender]
            .mul(_amount)
            .div(investorShares);

        // Burn tokens for this recipient
        houseToken.burn(msg.sender, _amount);

        // Send 50% profits to house
        uint256 houseProfits = 0;

        if (divestValue > originalValue) {
            houseProfits = divestValue
                .sub(originalValue)
                .div(2);

            beneficiary.transfer(houseProfits);
        }

        // Account reminder value of investor
        totalInvested -= bankrollMap[msg.sender];

        bankrollMap[msg.sender] = investorShares
            .sub(_amount)
            .mul(sharePrice);

        totalInvested += bankrollMap[msg.sender];

        // send payment
        uint256 reminder = divestValue - houseProfits;

        emit onDivest(msg.sender, reminder);

        msg.sender.transfer(reminder);
    }

    /**
     * @dev Internal share price calculation.
     * @param totalBalance balance in wei to base calculation on.
     */
    function _getSharePrice(uint256 totalBalance) internal view returns (uint256) {
        uint256 totalSupply = houseToken.totalSupply();
        if (totalSupply > 0) {
            return totalBalance.div(totalSupply);
        }
        return 1e5;
    }
}
