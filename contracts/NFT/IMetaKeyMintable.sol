pragma solidity ^0.8.0;

//interface class for mint in other NFT contract

interface IMetaKeyMintable {
    
    function mintFromMetaKey(uint _ticketId, address _nftOwner) external;
}
