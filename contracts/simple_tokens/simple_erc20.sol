pragma solidity ^0.8.0;

// import "./utils/SafeMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SimpleMGT is ERC20 {
    constructor() ERC20("Test20", "$T20"){

    }

    function mintForUser(address _userAddress, uint _amount) public {
        _mint(_userAddress, _amount);
    }
}

