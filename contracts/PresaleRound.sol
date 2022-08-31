pragma solidity ^0.8.0;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPresaleRound} from "./IPresaleRound.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

//for ERC777
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/interfaces/IERC1820Registry.sol";


contract MetagatePreSaleRound is ReentrancyGuard, IPresaleRound, Ownable, IERC777Recipient {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet WHITELIST;

    address public mgtContractAddress; // $MGT contract address
    uint256 public targetSaleAmount;   // target amount in this presale round
    uint256 public tokenSoldAmount;     // sold amount in this presale round

    mapping(address => uint256) tokenDeposit;
    mapping(address => uint256) tokenReleased;
    mapping(address => address) chainlinkFxAggregator;
    address[] public payTokenAddress;
    
    uint256 tokenPriceInUsd = 20;
    uint256 tokenPriceInUsdDecimal = 4;   // after all token price is 20 * 10**-4 = 0.0020 usd

    //in mainnet, this is 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
    address public ethFxAggregatorAddress = address(0x00);

    uint256 public releaseInterval = 7 days;
    uint256 public releaseRate = 35; // default release rate, means 3.5%

    uint256 public antiWhalePercent = 10; // default antiWhalePercent = 1%, there decimal is 3

    uint256 incrementValue; // token increment value, real increment value is incrementValue * 10 ** 18
    uint256 presaleStartTime; 
    uint256 presaleEndTime;

    PresaleRoundStatus public presaleRoundStatus = PresaleRoundStatus.NotStarted;
    uint256 _antiWhaleTokenAmount;
    uint8 public roundIndex;
    bool public isTokenWithdrawed;


    //erc 777
     //keccak256("ERC777TokensRecipient")
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH =
    0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;
    
    IERC1820Registry private _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);


    constructor() {
        // msg.sender is always Pegasus_Presale Contract
        _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }
    

    function init(address _tokenAddress, 
                uint _targetSaleAmount,
                uint _increment, 
                uint _releaseRate, 
                uint _tokenPriceInUsd, 
                uint _tokenPriceInUsdDecimal, 
                uint _antiWhalePercent, 
                uint8 _roundIndex 
    ) external override onlyOwner {

        targetSaleAmount = _targetSaleAmount;
        mgtContractAddress = _tokenAddress;
        incrementValue = _increment;
        releaseRate = _releaseRate;
        tokenPriceInUsd = _tokenPriceInUsd;
        tokenPriceInUsdDecimal = _tokenPriceInUsdDecimal;
        antiWhalePercent = _antiWhalePercent;
        _antiWhaleTokenAmount = targetSaleAmount.mul(antiWhalePercent).div(1000); // set the antiWhaleToken Amount
        roundIndex = _roundIndex; // round index eg 1, 2, 3, 4,
    }

    function startPresale() public override onlyOwner{
        require(presaleRoundStatus == PresaleRoundStatus.NotStarted, "Presale is started before!");
        IERC20 tokenContract = IERC20(mgtContractAddress);
        //CHECK if the contract have enough token
        require(tokenContract.balanceOf(address(this)) >= targetSaleAmount, "Presale Contract does not have enough tokens");
        presaleRoundStatus = PresaleRoundStatus.OnProgress;

        presaleStartTime = block.timestamp;
        //emit the PresaleStarted event
        emit PresaleStarted(roundIndex, block.timestamp, address(this));
        //event is emitted in the upper class.
    }

    function addERC20TokenForPay(address _erc20Address, address _aggregatorAddress) external override onlyOwner {
        // if the _erc20Address is already set just return
        if (chainlinkFxAggregator[_erc20Address] != address(0)) return;
        chainlinkFxAggregator[_erc20Address] = _aggregatorAddress;
        payTokenAddress.push(_erc20Address);
    }


    function buyTokenWithEth() external override payable nonReentrant {
        require(WHITELIST.contains(msg.sender), "Only whitelisted members can buy this token");
        require(presaleRoundStatus == PresaleRoundStatus.OnProgress, "Presale is not in progress");

        uint256 tokenBuyAmount;
        uint256 payAmount;
        // get tokenBuyAmount, payAmount;
        (tokenBuyAmount, payAmount) = _getSaleTokenAmount(msg.value, 18, ethFxAggregatorAddress);
        // require(tokenBuyAmount <= _antiWhaleTokenAmount, "Too much token buy request!");
        require(tokenBuyAmount >= incrementValue, "Too small token buy request");

        // if remaining token is less than the buy request
        if (tokenBuyAmount + tokenSoldAmount > targetSaleAmount) {
            // recalculate the tokenBuyAmount and payAmount
            uint newTokenBuyAmount = targetSaleAmount - tokenSoldAmount;
            payAmount = payAmount.mul(newTokenBuyAmount).div(tokenBuyAmount);
            tokenBuyAmount = newTokenBuyAmount;
        }

        //  check anti WhaleTokenAmount
        if (tokenDeposit[msg.sender] + tokenBuyAmount > _antiWhaleTokenAmount) {
            uint newTokenBuyAmount = targetSaleAmount - tokenSoldAmount;
            payAmount = payAmount.mul(newTokenBuyAmount).div(tokenBuyAmount);
            tokenBuyAmount = newTokenBuyAmount;
        }

        // add to deposit
        tokenDeposit[msg.sender] += tokenBuyAmount;
        tokenSoldAmount += tokenBuyAmount;
        //pay back remaining value
        payable(msg.sender).transfer(msg.value - payAmount);

        //check if the presale is end
        _checkIfEnd();
        emit Deposit(msg.sender, tokenBuyAmount, address(0x00), payAmount, block.timestamp);
    }

    function buyTokenWithERC20( address _tokenAddress, uint _tokenAmount) external override nonReentrant {
        require(WHITELIST.contains(msg.sender), "Only whitelisted members can buy this token");
        require(presaleRoundStatus == PresaleRoundStatus.OnProgress, "Presale is not in progress");
        ERC20 payTokenContract = ERC20(_tokenAddress);

        require(payTokenContract.allowance(msg.sender, address(this)) >= _tokenAmount, "Not allowed to use this token amount");

        // check the chainlink data feed address
        require(chainlinkFxAggregator[_tokenAddress] != address(0), "No fx is set for this token contract");

        uint256 tokenBuyAmount;
        uint256 payAmount;
        // get tokenBuyAmount, payAmount;
        (tokenBuyAmount, payAmount) = _getSaleTokenAmount(_tokenAmount, payTokenContract.decimals(), chainlinkFxAggregator[_tokenAddress]);

        require(tokenBuyAmount >= incrementValue, "Too small token buy request");

        // if remaining token is less than the buy request
        if (tokenBuyAmount + tokenSoldAmount > targetSaleAmount) {
            // recalculate the tokenBuyAmount and payAmount
            uint newTokenBuyAmount = targetSaleAmount - tokenSoldAmount;
            payAmount = payAmount.mul(newTokenBuyAmount).div(tokenBuyAmount);
            tokenBuyAmount = newTokenBuyAmount;
        }

        //  check anti WhaleTokenAmount
        if (tokenDeposit[msg.sender] + tokenBuyAmount > _antiWhaleTokenAmount) {
            uint newTokenBuyAmount = targetSaleAmount - tokenSoldAmount;
            payAmount = payAmount.mul(newTokenBuyAmount).div(tokenBuyAmount);
            tokenBuyAmount = newTokenBuyAmount;
        }

        // add to deposit
        tokenDeposit[msg.sender] += tokenBuyAmount;
        tokenSoldAmount += tokenBuyAmount;
        //transfer tokens
        payTokenContract.transferFrom(msg.sender, address(this), payAmount);

        //check if the presale is end
        _checkIfEnd();
        
        emit Deposit(msg.sender, tokenBuyAmount, address(_tokenAddress), payAmount, block.timestamp);

    }

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external override {
        operator;// to remove warning.
        to;
        userData;
        operatorData;

        
        address _tokenAddress = msg.sender;
        // require(msg.sender == address(_token), "XToken777Recipient: Invalid token");
        require(WHITELIST.contains(from), "Only whitelisted members can buy this token");
        require(presaleRoundStatus == PresaleRoundStatus.OnProgress, "Presale is not in progress");
        ERC20 payTokenContract = ERC20(_tokenAddress);

        // require(payTokenContract.allowance(msg.sender, address(this)) >= _tokenAmount, "Not allowed to use this token amount");

        // check the chainlink data feed address
        require(chainlinkFxAggregator[_tokenAddress] != address(0), "No fx is set for this token contract");

        uint256 tokenBuyAmount;
        uint256 payAmount;
        // get tokenBuyAmount, payAmount;
        (tokenBuyAmount, payAmount) = _getSaleTokenAmount(amount, payTokenContract.decimals(), chainlinkFxAggregator[_tokenAddress]);

        require(tokenBuyAmount >= incrementValue, "Too small token buy request");

        // if remaining token is less than the buy request
        if (tokenBuyAmount + tokenSoldAmount > targetSaleAmount) {
            // recalculate the tokenBuyAmount and payAmount
            uint newTokenBuyAmount = targetSaleAmount - tokenSoldAmount;
            payAmount = payAmount.mul(newTokenBuyAmount).div(tokenBuyAmount);
            tokenBuyAmount = newTokenBuyAmount;
        }

        //  check anti WhaleTokenAmount
        if (tokenDeposit[from] + tokenBuyAmount > _antiWhaleTokenAmount) {
            uint newTokenBuyAmount = targetSaleAmount - tokenSoldAmount;
            payAmount = payAmount.mul(newTokenBuyAmount).div(tokenBuyAmount);
            tokenBuyAmount = newTokenBuyAmount;
        }

        // add to deposit
        tokenDeposit[from] += tokenBuyAmount;
        tokenSoldAmount += tokenBuyAmount;
        
        //transfer remaining tokens
        payTokenContract.transfer(from, amount - payAmount);

        //check if the presale is end
        _checkIfEnd();
        
        emit Deposit(from, tokenBuyAmount, address(_tokenAddress), payAmount, block.timestamp);
    }

    //end the presale Round by owner
    function endPresaleRound() external override onlyOwner {
        require(presaleRoundStatus == PresaleRoundStatus.OnProgress);
        presaleRoundStatus = PresaleRoundStatus.Ended;
        presaleEndTime = block.timestamp;
        _endPresale();
        emit PresaleEnded(roundIndex, block.timestamp, tokenSoldAmount);
    }

    function getPresaleRoundStatus() external override view returns(PresaleRoundStatus) {
        return presaleRoundStatus;
    }


    function claimToken() external override nonReentrant {
        // require(
        //     block.timestamp > presaleEndTime,
        //     "release is not started yet"
        // );
        require(presaleRoundStatus == PresaleRoundStatus.Ended, "Presale is not ended yet");


        require(WHITELIST.contains(msg.sender), "msg.sender is not whitelisted.");

        IERC20 tokenContract = IERC20(mgtContractAddress);

        uint256 releaseRatioForInterval = (block.timestamp - presaleEndTime).div(releaseInterval);  // here only count the whole week. eg 3.4 week = 3 week
        releaseRatioForInterval = releaseRatioForInterval.mul(releaseRate);

        uint256 releaseAmountForSender = releaseRatioForInterval.mul(tokenDeposit[msg.sender]).div(1000);  // here decimal for ratio is 1000
        releaseAmountForSender = (releaseAmountForSender < tokenDeposit[msg.sender] ? releaseAmountForSender : tokenDeposit[msg.sender]);

        // transfer releaseAmount
        tokenContract.transfer(msg.sender, releaseAmountForSender - tokenReleased[msg.sender]);

        //emit event
        emit ReleaseToken(msg.sender, releaseAmountForSender - tokenReleased[msg.sender]);
        //update the releaseAmount
        tokenReleased[msg.sender] = releaseAmountForSender;
    }

    function getPresaleStatusForUser(address _userAddress) public view override returns(uint, uint) {
        return (tokenDeposit[_userAddress], tokenReleased[_userAddress]);
    }

    
    function editWhitelist(address[] memory _users, bool _add)
        external
        override
        onlyOwner
    {
        if (_add) {
            for (uint256 i = 0; i < _users.length; i++) {
                WHITELIST.add(_users[i]);
            }
        } else {
            for (uint256 i = 0; i < _users.length; i++) {
                WHITELIST.remove(_users[i]);
            }
        }
    }

    // whitelist getters
    function getWhitelistedUsersLength() external override view returns (uint256) {
        return WHITELIST.length();
    }

    function getWhitelistedUserAtIndex(uint256 _index)
        external
        view
        override
        returns (address)
    {
            return WHITELIST.at(_index);
            
    }

    function getUserWhitelistStatus(address _user)
        external
        view
        override
        returns (bool)
    {
        return WHITELIST.contains(_user);
    }


    // returns the tuple (realBuyTokenAmount, realPayAmount)
    function _getSaleTokenAmount(uint _payAmount, uint _payDecimal, address _aggregatorAddress) internal view returns(uint256, uint256) {
        AggregatorV3Interface aggregatorContract = AggregatorV3Interface(_aggregatorAddress);

        // get the lasted round value
        int256 payTokenInUsd;
        uint payTokenInUsdDecimal = aggregatorContract.decimals();
        (, payTokenInUsd,,,) = aggregatorContract.latestRoundData();
        //buyTokenAmount = payAmount * payTokenInUsd / mgtTokenPriceInUsd

        // ATTENTION : need to be check in dev test
        uint buyTokenAmount = _payAmount.div(10 ** _payDecimal);
        buyTokenAmount = buyTokenAmount.mul(uint256(payTokenInUsd));
        buyTokenAmount = buyTokenAmount.div(10 * payTokenInUsdDecimal);
        buyTokenAmount = buyTokenAmount.div(tokenPriceInUsd);
        buyTokenAmount = buyTokenAmount.mul(10 ** tokenPriceInUsdDecimal);
        
        uint realBuyTokenAmount = buyTokenAmount - (buyTokenAmount % incrementValue); // make realBuyTokenAmount 
        uint realPayAmount = _payAmount.mul(realBuyTokenAmount).div(buyTokenAmount);
        return (realBuyTokenAmount.mul(10 ** 18), realPayAmount);
    }

    function _checkIfEnd() internal {
        if ( (presaleRoundStatus == PresaleRoundStatus.OnProgress) && (targetSaleAmount - tokenSoldAmount < incrementValue) ) {
            presaleRoundStatus = PresaleRoundStatus.Ended;
            presaleEndTime = block.timestamp;
            _endPresale();
            emit PresaleEnded(roundIndex, block.timestamp, tokenSoldAmount);
        }
    }

    function _endPresale() private {
        // withdraw remaining mgt tokens
        IERC20 mgtContract = IERC20(mgtContractAddress);
        mgtContract.transfer(owner(), mgtContract.balanceOf(address(this)) - tokenSoldAmount);

        // withdraw the eth 
        payable(owner()).transfer(address(this).balance);

        //withdraw all pay tokens;
        for (uint i = 0; i < payTokenAddress.length; i++) {
            IERC20 tokenContract = IERC20(payTokenAddress[i]);
            tokenContract.transfer(owner(), tokenContract.balanceOf(address(this)));
        }
    }
    
}
