//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

// import "hardhat/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract MetagateVest is Ownable, ReentrancyGuard {

    address private _tokenAddress;
    using SafeMath for uint;
    uint public _releaseRate; // release rate for interval, eg 3.5% for week => 35
    uint public _releaseInterval; // release interval in the Vest contract, eg when 7days _releaseInterval = 7 days
    uint private _vestStartTime;
    uint private _vestEndTime;
    uint private _releaseEndTime;
    mapping(address => uint) private _vestedAmount;
    mapping(uint => address) private _vestedAddress;
    mapping(address => bool) private _vestedStatus;
    mapping(address => uint) private _releasedAmount;
    uint private _releaseStartTime;
    uint private _vestedAddressCount;
    IERC20 private _tokenContract;
    uint private _lastReleaseTime;
    bool private _releaseEnded;

    event VestToken(address vestedAddress, uint vestedAmount);
    event ReleaseToken(address releaseAddress, uint releaseAmount);
    event SetTokenAddress(address tokenAddress);
    
    constructor(
            uint vestStartTime,
             uint vestEndTime, 
             uint releaseRate, 
             uint releaseInterval, 
             uint releaseStartTime) 
             public Ownable(){
        require(vestStartTime < vestEndTime, "vesing start time is bigger than end time");
        require(vestEndTime < releaseStartTime, "release start time is bigger than vest end time");
        require(releaseInterval != 0, "release interval is zero");
        require(releaseRate != 0, "release rate is zero");

        _releaseRate = releaseRate;
        _releaseInterval = releaseInterval;
        _releaseStartTime = releaseStartTime;
        _vestStartTime = vestStartTime;
        _vestEndTime = vestEndTime;
        _releaseEndTime = _releaseStartTime + (1000 / _releaseRate + 1) * _releaseInterval;
        _releaseEnded = false;
        
        _lastReleaseTime = _releaseStartTime;
    }

    function setTokenAddress(address tokenAddress) public onlyOwner {
        _tokenAddress = tokenAddress;
        _tokenContract = IERC20(_tokenAddress);
        emit SetTokenAddress(tokenAddress);
    }

    function getCurrentVestStatus() public view returns(uint8) {
        if (block.timestamp < _vestStartTime) return 1; // No started yet
        if (block.timestamp > _vestEndTime) return 2; // vest Ended
        if (block.timestamp > _releaseStartTime) return 3; //release started;
        if (_releaseEnded) return 4; // release token ended;

        return 0; // vesting is on progress
    }

    function vestToken(uint amount) public {
        // require(block.timestamp >= _vestStartTime)
        require(getCurrentVestStatus() == 0, "vest is not on progress");

        //first transfer token
        _tokenContract.transferFrom(msg.sender, address(this), amount);

        if (_vestedStatus[msg.sender] == false) {
            _vestedStatus[msg.sender] = true;
            _vestedAddress[_vestedAddressCount ++ ] = msg.sender;
        }
        _vestedAmount[msg.sender] += amount;
        emit VestToken(msg.sender, _vestedAmount[msg.sender]);
    }

    function releaseToken() public nonReentrant {
        require(getCurrentVestStatus() == 3, "release is not started yet");

        //calculate the percent of the release token
        uint releasePercent = (block.timestamp - _lastReleaseTime) * _releaseRate / _releaseInterval;
        
        for (uint i = 0; i < _vestedAddressCount; i++) {
            address receiver = _vestedAddress[i];
            uint releaseAmount = _vestedAmount[receiver] * releasePercent / 1000;
            if (releaseAmount > (_vestedAmount[receiver] - _releasedAmount[receiver])) {
                releaseAmount = _vestedAmount[receiver] - _releasedAmount[receiver];
                _releaseEnded = true; 
            }

            _releasedAmount[receiver] += releaseAmount;
 
            // send the token to the receiver
            _tokenContract.transfer(receiver, releaseAmount);
            emit ReleaseToken(receiver, releaseAmount);
        }
    }
}


