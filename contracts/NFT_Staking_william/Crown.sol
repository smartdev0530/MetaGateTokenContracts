pragma solidity ^0.8.0;

// import "./utils/SafeMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CrownToken is ERC20 {

    // total supply for the token is 1 quadrillion.
    uint private _totalSupply = 10 ** 15 * 1 ether;


    //constructor function
    // Set token name, and total supply.
    constructor() ERC20("Crown", "$CWN"){     //Set name to "Crown"
        _mint(msg.sender, _totalSupply);   // mint all the tokens to the contract creator 
    }

    /**
     * ERC20 functions
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }    
}

