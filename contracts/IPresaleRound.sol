pragma solidity ^0.8.0;

interface IPresaleRound {

    enum PresaleRoundStatus {
        NotStarted,
        OnProgress,
        Ended
    }

    // Deposit event
    event Deposit(address indexed _from, uint256 _tokenAmount, address _payTokenContract, uint256 _payAmount, uint _timeStamp);
    //release token
    event ReleaseToken(address _releaseAddress, uint256 _value);
    event PresaleStarted(uint8 _roundInex, uint256 _timeStamp, address _presaleRoundAddress);
    event PresaleEnded(uint8 _roundInex, uint256 _timeStamp, uint256 _tokenSold);

    //initialize presale round 
    function init(address _tokenAddress, // token address
                uint _targetSaleAmount, // token sale goal
                uint _increment, 
                uint _releaseRate, 
                uint _tokenPriceInUsd, 
                uint _tokenPriceInUsdDecimal, 
                uint _antiWhalePercent, 
                uint8 _roundIndex) external;

    // start the presale round
    function startPresale() external;
    // add pay token address and its aggregator address
    function addERC20TokenForPay(address _erc20Address, address _aggregatorAddress) external;

    //buy token with native token
    function buyTokenWithEth() external payable;
    //buy token with the pay token
    function buyTokenWithERC20( 
        address _tokenAddress,  //pay token address
        uint _tokenAmount       //pay token amount
    ) external;
    // get the status of current round 
    function getPresaleRoundStatus() external view returns(PresaleRoundStatus);


    // end the token presale round manually
    function endPresaleRound() external;

    //user claims their token
    function claimToken() external;

    //get the presale status for the user, returns tuple(first : buyAmount, second : releaseAmount)
    function getPresaleStatusForUser(address _userAddress) external view returns(uint, uint);

    
    //edit the whitelist, _add = true => insert, add == false => remove
    function editWhitelist(address[] memory _users, bool _add) external;
    // get the whitelist
    function getWhitelistedUsersLength() external view returns (uint256);
    // get user at index
    function getWhitelistedUserAtIndex(uint256 _index) external view returns (address);
    //returns if the user is whitelisted.
    function getUserWhitelistStatus(address _user) external view returns (bool);
}

