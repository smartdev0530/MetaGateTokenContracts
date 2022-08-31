pragma solidity ^0.8.0;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
// import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PegasusPresale is Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public minimumDepositETHAmount = 0.3 ether; // Minimum deposit is 1 ETH
    uint256 public maximumDepositETHAmount = 3 ether; // Maximum deposit is 10 ETH

    uint256 public tokensPerETH = 1000; // token amount is 1000,
    uint public presaleTokenAmount = 500_000 ether; // pre sale token amount is 500K

    uint256 public presaleStartTime ; // 	Wed Mar 16 2022 15:00:00 GMT+0000
    uint256 public presaleEndTime ; // 	Sat Mar 26 2022 15:00:00 GMT+0000

    uint256 public firstReleaseTime ; 
    uint256 public secondReleaseTime ; 
    uint256 public thirdReleaseTime;

    uint public firstReleaseRate = 30;
    uint public secondReleaseRate = 30;  // accumulated rate 30 + 30
    uint public thirdReleaseRate = 40;

    address public erc20ContractAddress; // External erc20 contract

    uint256 public totalSaleAmount; // Total addresses' deposit amount

    EnumerableSet.AddressSet tokenBuyers;
    EnumerableSet.AddressSet secondReleasedSet;
    EnumerableSet.AddressSet thirdReleasedSet;

    address public usdtAddress = address(0x1234); // change the usdt address
    uint256 public tokensPerUsdt = 25; // here decimal is 1

    uint256 public minimumDepositUsdtAmount = 120 ether; // 120 usdt
    uint256 public maximumDepositUsdtAmount = 1200 ether; // Maximum 1200 usdt



    mapping(address => uint256) public depositAddressesETHAmount; // Address' deposit amount

    mapping(address => uint256)
        public depositAddressesAwardedTotalErc20CoinAmount; // Total awarded ERC20 coin amount for an address
    //   mapping(address => uint) public _depositAddressesAwardedDistribution1Erc20CoinAmount; // Awarded 1st distribution ERC20 coin amount for an address
    //   mapping(address => uint) public _depositAddressesAwardedDistribution2Erc20CoinAmount; // Awarded 2nd distribution ERC20 coin amount for an address
    mapping(address => uint256) public releasedAmount;
    mapping(address => uint256) public referalBonus;
    mapping(address => uint) public lastReleaseTime;


    // Deposit event
    event Deposit(address indexed _from, uint256 _value, address _referal);
    event DepositWithUSDT(address indexed _from, uint256 _value, address _referal);

    //release token
    event ReleaseToken(address releaseAddress, uint256 value);

    //distribute token (by admin)
    event DistributeSecond(uint _timeStamp);
    event DistributeThird(uint _timeStamp);



    constructor(address _tokenAddress) {
        erc20ContractAddress = _tokenAddress;
    }


    // token transfer
    function initialize() public  {
        IERC20 tokenContract = IERC20(erc20ContractAddress);
        tokenContract.transferFrom(msg.sender, address(this), presaleTokenAmount);
        presaleStartTime = block.timestamp;  // set the presale start time
        presaleEndTime = presaleStartTime + 1 days; // set the presale end time
        firstReleaseTime = block.timestamp;
        secondReleaseTime = firstReleaseTime + 20 days;
        thirdReleaseTime = secondReleaseTime + 20 days;
    }

    
    // Receive ETH deposit
    function deposit(address _referal) public payable {
        require(
            block.timestamp >= presaleStartTime &&
                block.timestamp <= presaleEndTime,
            "Deposit rejected, presale has either not yet started or not yet overed"
        );

        require(tokenBuyers.contains(msg.sender) == false, "This address has bought the token before");

        
        require(
            msg.value >= minimumDepositETHAmount,
            "Deposit rejected, it is lesser than minimum amount"
        );

        require(
            msg.value <= maximumDepositETHAmount,
            "Deposit rejected, it is more than maximum amount"
        );

        uint tokenForBuyer = msg.value.mul(tokensPerETH);
        uint tokenForReferal = 0;
        if (tokenBuyers.contains(_referal)) {
            tokenForReferal = tokenForBuyer.mul(5).div(100); // referal tokens
        }

        if (totalSaleAmount.add(tokenForBuyer).add(tokenForReferal) > presaleTokenAmount) {
            // if remaining token is less than the tokens for buyer
            uint256 newTokenForBuyer;
            uint256 newTokenForReferal;
            uint256 tokenRemaining = presaleTokenAmount.sub(totalSaleAmount);
            newTokenForBuyer = tokenRemaining.mul(tokenForBuyer).div(tokenForBuyer + tokenForReferal);
            newTokenForReferal = tokenRemaining.mul(tokenForReferal).div(tokenForBuyer + tokenForReferal);
            
            tokenForBuyer = newTokenForBuyer;
            tokenForReferal = newTokenForReferal;

            //send the remaining value
            uint priceToBuyRemain = tokenForBuyer.div(tokensPerETH);
            if (priceToBuyRemain < msg.value) payable(msg.sender).transfer(msg.value.sub(priceToBuyRemain));
        }

        depositAddressesAwardedTotalErc20CoinAmount[msg.sender] = tokenForBuyer;
        if (tokenBuyers.contains(_referal)) {
            // depositAddressesAwardedTotalErc20CoinAmount[_referal] += tokenForReferal;
            referalBonus[_referal] += tokenForReferal;
        }

        //calculate totalSaleAmount
        totalSaleAmount = totalSaleAmount.add(tokenForBuyer).add(tokenForReferal);

        //add msg.sender to token buyers
        tokenBuyers.add(msg.sender);

        //send the 30 % of the token
        IERC20 tokenContract = IERC20(erc20ContractAddress);
        uint releaseTokenCount = tokenForBuyer.mul(firstReleaseRate).div(100);

        releasedAmount[msg.sender] += releaseTokenCount;

        tokenContract.transfer(msg.sender, releaseTokenCount);
        emit Deposit(msg.sender, msg.value, _referal);
        emit ReleaseToken(msg.sender, releaseTokenCount);
    }

    function buyTokenWithUsdt(uint256 _usdtAmount, address _referal) public {

        require(
            block.timestamp >= presaleStartTime &&
                block.timestamp <= presaleEndTime,
            "Deposit rejected, presale has either not yet started or not yet overed"
        );

        require(tokenBuyers.contains(msg.sender) == false, "This address has bought the token before");

        require(
            _usdtAmount >= minimumDepositETHAmount,
            "Deposit rejected, it is lesser than minimum amount"
        );

        require(
            _usdtAmount <= maximumDepositETHAmount,
            "Deposit rejected, it is more than maximum amount"
        );

        IERC20 usdtContract = IERC20(usdtAddress);
        require(usdtContract.allowance(msg.sender, address(this)) >= _usdtAmount, "Contract is not allowed to transfer token");

        uint tokenForBuyer = _usdtAmount.mul(tokensPerETH).div(10); // here decimal is 1
        uint tokenForReferal = 0;

        if (tokenBuyers.contains(_referal)) {
            tokenForReferal = tokenForBuyer.mul(5).div(100); // referal tokens
        }

        if (totalSaleAmount.add(tokenForBuyer).add(tokenForReferal) > presaleTokenAmount) {
            // if remaining token is less than the tokens for buyer
            uint256 newTokenForBuyer;
            uint256 newTokenForReferal;
            uint256 tokenRemaining = presaleTokenAmount.sub(totalSaleAmount);
            newTokenForBuyer = tokenRemaining.mul(tokenForBuyer).div(tokenForBuyer + tokenForReferal);
            newTokenForReferal = tokenRemaining.mul(tokenForReferal).div(tokenForBuyer + tokenForReferal);
            
            tokenForBuyer = newTokenForBuyer;
            tokenForReferal = newTokenForReferal;

            //send the remaining value
            uint priceToBuyRemain = tokenForBuyer.div(tokensPerUsdt).mul(10); // here decimal is 1
            //change _usdtAmount
            _usdtAmount = priceToBuyRemain;

            // if (priceToBuyRemain < msg.value) payable(msg.sender).transfer(msg.value.sub(priceToBuyRemain));
        }

        depositAddressesAwardedTotalErc20CoinAmount[msg.sender] = tokenForBuyer;
        if (tokenBuyers.contains(_referal)) {
            // depositAddressesAwardedTotalErc20CoinAmount[_referal] += tokenForReferal;
            referalBonus[_referal] += tokenForReferal;
        }

        //calculate totalSaleAmount
        totalSaleAmount = totalSaleAmount.add(tokenForBuyer).add(tokenForReferal);

        //add msg.sender to token buyers
        tokenBuyers.add(msg.sender);

        //send the 30 % of the token
        IERC20 tokenContract = IERC20(erc20ContractAddress);
        uint releaseTokenCount = tokenForBuyer.mul(firstReleaseRate).div(100);

        releasedAmount[msg.sender] += releaseTokenCount;

        tokenContract.transfer(msg.sender, releaseTokenCount);

        //send the usdt
        usdtContract.transferFrom(msg.sender, address(this), _usdtAmount);

        emit DepositWithUSDT(msg.sender, _usdtAmount, _referal);
        emit ReleaseToken(msg.sender, releaseTokenCount);
    }

    function claimTokenSecond() public {
        require(tokenBuyers.contains(msg.sender), "Address is not in the buyer list");
        require(!secondReleasedSet.contains(msg.sender), "Second release already done");
        require(block.timestamp > secondReleaseTime, "Not yet for second release");

        IERC20 tokenContract = IERC20(erc20ContractAddress);
        uint releaseTokenCount = depositAddressesAwardedTotalErc20CoinAmount[msg.sender].mul(secondReleaseRate).div(100);
        releasedAmount[msg.sender] += releaseTokenCount;

        // add msg.sender to the address set
        secondReleasedSet.add(msg.sender);


        tokenContract.transfer(msg.sender, releaseTokenCount);
        emit ReleaseToken(msg.sender, releaseTokenCount);
    }

    function distributeSecond() public {
        require(block.timestamp > secondReleaseTime, "Not yet for second release");

        uint buyerCount = tokenBuyers.length();
        IERC20 tokenContract = IERC20(erc20ContractAddress);

        for (uint i = 0; i < buyerCount; i ++) {
            address buyerAddress = tokenBuyers.at(i);
            if (secondReleasedSet.contains(buyerAddress)) continue;
            secondReleasedSet.add(buyerAddress);

            uint releaseTokenCount = depositAddressesAwardedTotalErc20CoinAmount[buyerAddress].mul(secondReleaseRate).div(100);
            releasedAmount[buyerAddress] += releaseTokenCount;
            tokenContract.transfer(msg.sender, releaseTokenCount);            
        }
        emit DistributeSecond(block.timestamp);
    }

    function claimTokenThird() public {
        require(tokenBuyers.contains(msg.sender), "Address is not in the buyer list");
        require(!thirdReleasedSet.contains(msg.sender), "Third release already done");
        require(block.timestamp > thirdReleaseTime, "Not yet for third release");


        IERC20 tokenContract = IERC20(erc20ContractAddress);
        //release amount is 40 % + referal bonus
        uint releaseTokenCount = depositAddressesAwardedTotalErc20CoinAmount[msg.sender].mul(thirdReleaseRate).div(100) + referalBonus[msg.sender];
        releasedAmount[msg.sender] += releaseTokenCount;

        // add msg.sender to the address set
        thirdReleasedSet.add(msg.sender);

        tokenContract.transfer(msg.sender, releaseTokenCount);
        emit ReleaseToken(msg.sender, releaseTokenCount);
    }

    function distributeThird() public {
        require(block.timestamp > thirdReleaseTime, "Not yet for third release");

        uint buyerCount = tokenBuyers.length();
        IERC20 tokenContract = IERC20(erc20ContractAddress);

        for (uint i = 0; i < buyerCount; i ++) {
            address buyerAddress = tokenBuyers.at(i);

            if (thirdReleasedSet.contains(buyerAddress)) continue;
            thirdReleasedSet.add(buyerAddress);

            uint releaseTokenCount = depositAddressesAwardedTotalErc20CoinAmount[buyerAddress].mul(thirdReleaseRate).div(100) + referalBonus[buyerAddress];
            releasedAmount[buyerAddress] += releaseTokenCount;
            tokenContract.transfer(msg.sender, releaseTokenCount);            
        }
        emit DistributeThird(block.timestamp);
    }



    // Allow admin to withdraw all the deposited ETH
    function withdrawAll() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    // withdraw remaining tokes 
    function withdrawPegasusToken() public onlyOwner {
        IERC20 tokenContract = IERC20(erc20ContractAddress);
        tokenContract.transfer(owner(), presaleTokenAmount - totalSaleAmount);
    }

    function getPresaleAmount(address _address) public view returns(uint256) {
        return depositAddressesAwardedTotalErc20CoinAmount[_address] + referalBonus[_address];
    }

    function getReleasedAmount(address _address) public view returns(uint256) {
        return releasedAmount[_address];
    }
    
}
