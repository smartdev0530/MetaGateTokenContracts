pragma solidity ^0.8.0;

// import "./utils/SafeMath.sol";
import {ERC777} from "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Metagate is ERC777 {
    using SafeMath for uint256;

    // ERC20 variables
    //   mapping(address => uint) private _balances;
    //   mapping(address => mapping(address => uint)) private _allowances;
    uint256 private _totalSupply = 10_000_000_000 * 10 ** 18; // 10B

    // General variables
    address public _admin;

    address public _presaleContract;
    address public _teamContract;
    address public _advisorContract;
    address public _lpControlContract;
    address public _devAndPartnershipAddress;
    address public _communityTreasuryAddress;
    address public _rewardsAddress;

    address[] private _tokenOwners;
    uint256 private _tokenOwnersCount;

    constructor(
        address presaleAddress,
        address teamAddress,
        address advisorAddress,
        address lpConrolAddress,
        address devAndPartenershipAddress,
        address communitTreasuryAddress,
        address rewardsAddress
    ) public ERC777("Metagate", "$METAGATE", new address[](0)) {
        _admin = msg.sender;
        // Add all addresses
        _presaleContract = presaleAddress;
        _teamContract = teamAddress;
        _advisorContract = advisorAddress;
        _lpControlContract = lpConrolAddress;
        _devAndPartnershipAddress = devAndPartenershipAddress;
        _communityTreasuryAddress = communitTreasuryAddress;
        _rewardsAddress = rewardsAddress;

        _mint(address(this), _totalSupply, "", "");

        transfer(_presaleContract, _totalSupply.mul(23).div(100)); // for the presale contract we give 23 % of totalSupply
        transfer(_teamContract, _totalSupply.mul(12).div(100)); //for team 12 %
        transfer(_advisorContract, _totalSupply.mul(3).div(100)); // 3 % for adviser
        transfer(_lpControlContract, _totalSupply.mul(7).div(100)); // 7% for LP
        transfer(_devAndPartnershipAddress, _totalSupply.mul(15).div(100)); // 15 % for dev and partnership
        transfer(_communityTreasuryAddress, _totalSupply.mul(25).div(100)); // 25 % for community
        transfer(_rewardsAddress, _totalSupply.mul(15).div(100)); // 15% for rewards
    }

    /**
     * ERC20 functions
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * override transfer function
     */

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        if (balanceOf(recipient) == 0) {
            _tokenOwners.push(recipient);
        }
        return super.transfer(recipient, amount);
    }

    /**
     * override transferFrom function
     */

    function transferFrom(
        address holder,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        if (balanceOf(recipient) == 0) {
            _tokenOwners.push(recipient);
        }
        return super.transferFrom(holder, recipient, amount);
    }

    function _send(
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData,
        bool requireReceptionAck
    ) internal virtual override {
        if (balanceOf(to) == 0) {
            _tokenOwners.push(to);
        }
        super._send(
            from,
            to,
            amount,
            userData,
            operatorData,
            requireReceptionAck
        );
    }

    function getAllOwners() public view returns(address[] memory){
        return _tokenOwners;
    }
}
