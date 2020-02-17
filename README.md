# State Channels

## 1 - Open channel

- Client sends a deposit promise, with nonce 0:
    `msgHash = hash(sender.address, depositValue, 0);`

- Server verifies msgHash OK and signs:
    `serverSignature = sign(msgHash);`

- Client open channel with promised payment:
    `openChannel(msgHash, serverSignature);`

The contract will then return a `channelId` for use in future communications.


## 2 - Update channel balance

Similar to the previous scenario, the client now uses the opened channelId. 

- Client sends a deposit promise:
    `msgHash = hash(channelId, depositValue, 0);`

- Server verifies msgHash OK and signs:
    `serverSignature = sign(msgHash);`

- Client updates channel with promised payment:
    `updateChannel(msgHash, serverSignature);`

Here the client may try to trick and provided with the server signature he might decide not to top-up the channel with the promised value, but instead use the `serverSignature` to initiate a channel dispute. 

Note here that the `nonce` in the `msgHash` is 0, and the contract will enforce the disputed value to be exactly equal to the channel balace (on the blockchain) when deciding for a nonce = 0 message. The server will still have chance to challenge and provide its dispute evidence. 


## 3 - Close by agreement

- Client notifies server it wishes to close the channel and sends:
    `msgHash = hash(channelId, channelBalance, currentNonce);`
    `clientSignature = sign(msgHash);`

- Server verifies msgHash and client signatures and calls:
    `closeChannel(msgHash, clientSignature);`


## 4 - Client dispute

- Client decides to open a dispute and calls:
    `openDispute(channelId);`

- Each party then has a time window to send valid proofs:
    `setDisputeEvidence(msgHash, otherPartySignature, channelBalance, nonce);`

- After the dispute period, any address can settle the dispute and close the channel. 
    `closeDispute(bytes32 _channelId);`

# ethgames-contracts
