pragma solidity ^0.5.12;

import "../node_modules/openzeppelin-eth/contracts/ownership/Ownable.sol";
import "../node_modules/openzeppelin-eth/contracts/cryptography/ECDSA.sol";


contract StateChannel is Ownable {

    using ECDSA for bytes32;

    event onChannelOpen(address indexed origin, bytes32 indexed channelId, uint256 amount);
    event onChannelClose(address indexed origin, bytes32 indexed channelId, uint256 amount);
    event onChannelUpdate(address indexed origin, bytes32 indexed channelId, uint256 amount);
    event onChannelDispute(address indexed origin, bytes32 indexed channelId);
    event onDisputeEvidence(address indexed origin, bytes32 indexed channelId, uint256 nonce, uint256 value);
    event onTransferAdmin(address indexed previousAdmin, address indexed newAdmin);

    enum ChannelStatus { CLOSED, DISPUTED, OPEN }

    struct Channel {
        address payable client;
        address signerAddress;
        uint256 clientDeposit;
        ChannelStatus status;
    }

    struct Dispute {
        uint256 disputeDeadline;
        uint256 disputeValue;
        uint256 disputeNonce;
    }

    mapping (bytes32 => Channel) channels;
    mapping (bytes32 => Dispute) disputes;

    mapping (address => bytes32) activeIds;

    address private _contractAdmin;

    function initialize(address sender) public initializer {
        Ownable.initialize(sender);

        // set admin to contract initializer
        _contractAdmin = newAdmin;
    }

    /**
     * @dev Transfers channel admin address of the contract to a newAdmin
     * @param newAdmin The address to transfer admin to.
     */
    function setAdminAddress(address newAdmin) public onlyOwner {
        require(newAdmin != address(0), "newAdmin invalid");
        _contractAdmin = newAdmin;
        emit onTransferAdmin(_contractAdmin, newAdmin);
    }

    /**
     * @dev Returns channelId for provided address
     */
    function getChannelId(address _from) public view returns (bytes32) {
        return activeIds[_from];
    }

    /**
     * @dev Returns channel total deposit for provided address
     */
    function getChannelBalance(address _from) public view returns (uint256) {
        bytes32 channelId = getChannelId(_from);
        return channels[channelId].clientDeposit;
    }

    /**
     * @dev Returns channel total deposit for provided address
     */
    function getChannelSigner(address _from) public view returns (address) {
        bytes32 channelId = getChannelId(_from);
        return channels[channelId].signerAddress;
    }

    /**
     * @dev Verifies a signature against an address
     * @param _msgHash provided signature
     * @param _signature provided signature
     * @param _signer address to check against
     */
    function verifySignature(
        bytes32 _msgHash,
        bytes memory _signature,
        address _signer
    )
        public pure returns (bool)
    {
        address addr = _msgHash
            .toEthSignedMessageHash()
            .recover(_signature);

        return (addr == _signer);
    }

    /**
     * @dev Verifies a provided message hash(channelId, value, nonce)
     * @param _msgHash provided hash
     * @param _channelId variable to hash
     * @param _value variable to hash
     * @param _nonce variable to hash
     */
    function verifyMessage(
        bytes32 _msgHash,
        bytes32 _channelId,
        uint256 _value,
        uint256 _nonce
    )
        public pure returns (bool)
    {
        bytes32 proof = keccak256(
            abi.encodePacked(_channelId, _value, _nonce)
        );
        return (proof == _msgHash);
    }

    /**
     * @dev Open state channel for sender.
     * @param _msgHash Hash of (bytes32(sender), deposit, 0)
     * @param _depositValue Aggreed channel deposit by server
     * @param _signerAddress signer of the channel
     * @param _serverSignature server signature
     */
    function openChannel(
        bytes32 _msgHash,
        uint256 _depositValue,
        address _signerAddress,
        bytes memory _serverSignature
    )
        public payable
    {
        // Checks value and not already open.
        require(activeIds[msg.sender] == bytes32(0), "sender has already an open channel");

        require(msg.sender != _contractAdmin, "sender should be != _contractAdmin");
        require(msg.value == _depositValue, "msg.value should be == _depositValue");

        bytes32 addrHash = keccak256(abi.encodePacked(msg.sender));

        // Verify open channel hash and signature
        require(verifyMessage(_msgHash, addrHash, _depositValue, 0), "invalid msgHash");
        require(verifySignature(_msgHash, _serverSignature, _contractAdmin), "invalid signature");

        // solhint-disable-next-line not-rely-on-time
        bytes32 channelId = keccak256(
            abi.encodePacked(msg.sender, address(this), block.timestamp)
        );

        channels[channelId] = Channel({
            client: msg.sender,
            clientDeposit: msg.value,
            signerAddress: _signerAddress,
            status: ChannelStatus.OPEN
        });

        // Add it to the lookup table
        activeIds[msg.sender] = channelId;

        emit onChannelOpen(msg.sender, channelId, msg.value);
    }

    /**
     * @dev update balance an opened channel
     * @param _channelId Channel Id
     * @param _msgHash Hash of (channel Id, deposit, 0)
     * @param _depositValue Aggreed channel deposit by server
     * @param _serverSignature server signature
     */
    function addBalanceToChannel(
        bytes32 _channelId,
        bytes32 _msgHash,
        uint256 _depositValue,
        bytes memory _serverSignature
    )
        public payable
    {
        Channel storage ch = channels[_channelId];

        // Check open channel and updater party is participant
        require(msg.sender == ch.client, "invalid msg.sender");
        require(msg.value == _depositValue, "msg.value should be == _depositValue");

        require(ch.status == ChannelStatus.OPEN, "channel is not OPEN");

        // Verify open channel hash and signature
        require(verifyMessage(_msgHash, _channelId, _depositValue, 0), "invalid msgHash");
        require(verifySignature(_msgHash, _serverSignature, _contractAdmin), "invalid signature");

        // Add funds to channel
        ch.clientDeposit += msg.value;

        emit onChannelUpdate(msg.sender, _channelId, ch.clientDeposit);
    }

    /**
     * @dev Close an prevously opened channel, agreed by both parties
     *  only called by _contractAdmin
     * @param _channelId Channel Id
     * @param _msgHash Hash of (channel Id, balance, nonce)
     * @param _finalBalance Aggreed channel balance by parties
     * @param _nonce Aggreed nonce by parties
     * @param _clientSignature client signature on the closeMsg
     */
    function closeChannel(
        bytes32 _channelId,
        bytes32 _msgHash,
        uint256 _finalBalance,
        uint256 _nonce,
        bytes memory _clientSignature
    )
        public
    {
        Channel storage ch = channels[_channelId];

        // Check closing party is _contractAdmin and channel is open
        require(msg.sender == _contractAdmin, "invalid msg.sender");
        require(ch.status == ChannelStatus.OPEN, "channel is not OPEN");

        // Verify correct server message
        require(verifyMessage(_msgHash, _channelId, _finalBalance, _nonce), "invalid msgHash");
        require(verifySignature(_msgHash, _clientSignature, ch.client), "invalid signature");

        _closeChannel(_channelId, _finalBalance);
    }

    /**
     * @dev Client does not agree and decides to open a dispute
     * @param _channelId Channel Id
     */
    function openDipute(bytes32 _channelId) public {
        Channel storage ch = channels[_channelId];

        // Check participant
        require(msg.sender == ch.client, "invalid msg.sender");
        require(ch.status == ChannelStatus.OPEN, "channel is not OPEN");

        // Sets channel on disputed state
        ch.status = ChannelStatus.DISPUTED;

        disputes[_channelId] = Dispute({
            disputeNonce: 0,
            disputeValue: 0,
            disputeDeadline: block.timestamp + 15 minutes
        });

        emit onChannelDispute(msg.sender, _channelId);
    }

    /**
     * @dev Each party can submit their valid evidence on the dispute period
     * @param _channelId Channel Id
     * @param _msgHash Hash of (channel Id, value, nonce)
     * @param _partySignature server signature
     * @param _channelBalance Aggreed balance spent by parties
     * @param _nonce Aggreed nonce by parties
     */
    function setDisputeEvidence(
        bytes32 _channelId,
        bytes32 _msgHash,
        bytes memory _partySignature,
        uint256 _channelBalance,
        uint256 _nonce
    )
        public
    {
        Channel storage ch = channels[_channelId];
        Dispute storage dp = disputes[_channelId];

        // Check can provide proof
        require(ch.status == ChannelStatus.DISPUTED, "channel not on dispute");
        require(dp.disputeDeadline < block.timestamp, "channel dispute period ended");

        // Check participants
        require(msg.sender == ch.client || msg.sender == _contractAdmin, "invalid msg.sender");

        // Verify correct message
        require(verifyMessage(_msgHash, _channelId, _channelBalance, _nonce), "invalid msgHash");

        // If sender is client, verify server signature.
        if (msg.sender == ch.client) {
            require(
                verifySignature(_msgHash, _partySignature, _contractAdmin),
                "invalid server signature"
            );

        // If sender is server, verifies channel signer
        } else {
            require(
                verifySignature(_msgHash, _partySignature, ch.signerAddress),
                "invalid signature (channel signer)"
            );
        }

        // Special case: the client dispute and sends the deposit message as proof.
        if (msg.sender == ch.client && _nonce == 0) {
            dp.disputeValue = ch.clientDeposit;

        // Highest nonce we see sets the dispute value
        } else if (_nonce > dp.disputeNonce) {
            dp.disputeNonce = _nonce;
            dp.disputeValue = _channelBalance;
        }

        emit onDisputeEvidence(msg.sender, _channelId, _nonce, _channelBalance);
    }

    /**
     * @dev Anyone can close a disputed channel after dispute period
     * @param _channelId Channel Id
     */
    function closeDispute(bytes32 _channelId) public {
        Channel storage ch = channels[_channelId];
        Dispute storage dp = disputes[_channelId];

        require(ch.status == ChannelStatus.DISPUTED, "channel is not on dispute");
        require(dp.disputeDeadline >= block.timestamp, "channel dispute period is not ended");

        _closeChannel(_channelId, dp.disputeValue);
    }

    /**
     * @dev Internal function to close the channel,
     *  and transfer agreed value to client
     * @param _channelId to close and free resources
     * @param _value to transfer
     */
    function _closeChannel(bytes32 _channelId, uint256 _value) internal {
        address payable client = channels[_channelId].client;

        // Delete channel
        delete activeIds[client];
        delete channels[_channelId];
        delete disputes[_channelId];

        client.transfer(_value);

        emit onChannelClose(client, _channelId, _value);
    }
}