pragma solidity ^0.8.0;

import {MetagatePreSaleRound} from "./PresaleRound.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPresaleRound} from "./IPresaleRound.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract MetagatePresale is Ownable, ReentrancyGuard {

    address public tokenAddress;
    IPresaleRound[] public presaleRounds;
    uint8 presaleRoundCount = 0;
    uint8 nextAvailabeRoundIndex = 0;

    // IMPORTANT : this address will be used in the frontend as a presale round
    address public currentPresaleRoundAddress; // current presale round that is on the progress

    mapping(address => address) chainlinkFxAggregator;
    address[] public payTokenAddress;

    event PresaleRoundStarted(uint8  _roundIndex, uint256 _timeStamp );
    event WithdrawToken(uint256 _withdrawAmount);

    constructor() {

    }

    function setTokenAddress(address _tokenAddress) public onlyOwner {
        tokenAddress = _tokenAddress;
    }
    
    //This is the example function to add presale round 1
    function activatePresale1() public onlyOwner {
        
        addPresaleRound(10000000 ether, 
            1000, //increment value ( means 1000 * 10 ** 18 include decimals)
            35, 
            5, // 0.005 is 5 with decimal 3 
            3, // 
            10 // anti whale is 1% 
        );
        // // start the presale round 0;
        // presaleRounds[0].startPresale();
    }

    // add presale round, can add dynamically just calling this function
    function addPresaleRound(
        uint _targetSaleAmount,
        uint _increment, 
        uint _releaseRate, 
        uint _tokenPriceInUsd, 
        uint _tokenPriceInUsdDecimal, 
        uint _antiWhalePercent // here decimal is 3, so 1% is 10
        ) public onlyOwner
    {

        require(tokenAddress != address(0), "Token address is not set yet");
        MetagatePreSaleRound presaleRound  = new MetagatePreSaleRound();
        // presale1.setToken(tokenAddress);
        //init the presale 1
        presaleRound.init(
            tokenAddress,
            _targetSaleAmount, 
            _increment,
            _releaseRate, 
            _tokenPriceInUsd, 
            _tokenPriceInUsdDecimal, 
            _antiWhalePercent, 
            presaleRoundCount
        );

        //send token to the contract
        IERC20 tokenContract = IERC20(tokenAddress);
        tokenContract.transfer(address(presaleRound), presaleRound.targetSaleAmount() );
        presaleRounds.push(presaleRound);
        presaleRoundCount ++;
    }

    // add the pay token to presale contract
    function addERC20TokenForPay(address _erc20Address, address _aggregatorAddress) external onlyOwner {
        // if the _erc20Address is already set just return
        if (chainlinkFxAggregator[_erc20Address] != address(0)) return;

        chainlinkFxAggregator[_erc20Address] = _aggregatorAddress;
        payTokenAddress.push(_erc20Address);

        //add to prev existing presale round 
        for (uint i = 0; i < presaleRounds.length; i++) {
            presaleRounds[i].addERC20TokenForPay(_erc20Address, _aggregatorAddress);
        }
    }

    function startPresaleRound(uint8 _roundIndex) public onlyOwner {
        require(_roundIndex < presaleRoundCount, "No presale round with the index");

        //make sure add erc20 token for pay to the _round
        for (uint i = 0; i < payTokenAddress.length; i++) {
            presaleRounds[_roundIndex].addERC20TokenForPay(payTokenAddress[i], chainlinkFxAggregator[payTokenAddress[i]]);
        }

        if (_roundIndex == 0) {
            // if (currentRoundIndex )
            presaleRounds[0].startPresale();
            emit PresaleRoundStarted(0, block.timestamp);
            currentPresaleRoundAddress = address(presaleRounds[0]);
            //set the next available round index
            nextAvailabeRoundIndex = 1;
            return;
        }

        require(presaleRounds[_roundIndex - 1].getPresaleRoundStatus() == IPresaleRound.PresaleRoundStatus.Ended, "Previous presale is not ended yet");
        presaleRounds[_roundIndex].startPresale();
        // set the current presale round address
        currentPresaleRoundAddress = address(presaleRounds[_roundIndex]);
        // set the next availabe round index
        nextAvailabeRoundIndex = _roundIndex + 1;
        emit PresaleRoundStarted(_roundIndex, block.timestamp);
    } 

    // end the presale round manually
    function endCurrentPresaleRound() public onlyOwner {
        require(currentPresaleRoundAddress != address(0), "There's no current available presale round");
        IPresaleRound(currentPresaleRoundAddress).endPresaleRound();
    }

    // get the current presale round status 
    function getCurrentPresaleRoundStatus() public view returns(IPresaleRound.PresaleRoundStatus) {
        require(currentPresaleRoundAddress != address(0), "There's no current available presale round");
        return IPresaleRound(currentPresaleRoundAddress).getPresaleRoundStatus();
    }

    // withdraw eth, and all pay tokens
    function withdrawAll() external onlyOwner {
        // withdraw the eth 
        payable(owner()).transfer(address(this).balance);

        //withdraw all pay tokens;
        for (uint i = 0; i < payTokenAddress.length; i++) {
            IERC20 tokenContract = IERC20(payTokenAddress[i]);
            tokenContract.transfer(owner(), tokenContract.balanceOf(address(this)));
        }
    }


    //withdraw tokens from the presale rounds
    function withdrawRemainingTokens() external onlyOwner{
        //require all the presale is over
        require((getCurrentPresaleRoundStatus() == IPresaleRound.PresaleRoundStatus.Ended) && nextAvailabeRoundIndex == presaleRoundCount, 
            "All presale round is not ended yet");

        IERC20 tokenContract = IERC20(tokenAddress);
        uint withdrawAmount = tokenContract.balanceOf(address(this));
        tokenContract.transfer(owner(), withdrawAmount);

        emit WithdrawToken(withdrawAmount);
    }

    function getTotalPresaleRoundCount() external view returns (uint) {
        return presaleRounds.length;
    }

    function getPresaleRoundAddress(uint index) public view returns(address) {
        require(index < presaleRounds.length);
        return address(presaleRounds[index]);
    }

    function getCurrentPresaleRoundAddress() public view returns(address) {
        return currentPresaleRoundAddress;
    }
    
}