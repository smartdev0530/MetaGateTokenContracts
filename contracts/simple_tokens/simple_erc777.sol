pragma solidity ^0.8.0;

// import "./utils/SafeMath.sol";
import {ERC777} from "@openzeppelin/contracts/token/ERC777/ERC777.sol";

contract SimpleMGT is ERC777 {
    constructor() ERC777("SimpleMGT", "$SMGT", new address[](0)){

    }

    function mintForUser(address _userAddress, uint _amount) public {
        _mint(_userAddress, _amount, "", "");
    }
}

