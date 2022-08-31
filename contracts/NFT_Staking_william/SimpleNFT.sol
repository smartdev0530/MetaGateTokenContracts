pragma solidity ^0.8.0;

// import "./utils/SafeMath.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract SimpleMGT is ERC721 {
    uint private _totalSupply = 0;
    constructor() ERC721("Test721", "SimpleNFT"){

    }

    

    function mintForUser(address _userAddress) public {
        _mint(_userAddress, _totalSupply);
        _totalSupply++;
    }
}

