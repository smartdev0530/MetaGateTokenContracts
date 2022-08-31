pragma solidity ^0.8.0;

//interface class for mint in other NFT contract
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IMasterKeyMintable is IERC721{
    
    function getTokenId() external returns(uint);
    function mintFromMasterKey() external returns(uint);
}
