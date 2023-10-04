// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract PintAirdrop{

    IERC20 pintToken;

    struct Claims{
    address claimAddress;
    uint256 claimAmount;
    uint256 claimTime;
    }

    struct ClaimInfo{
    address claimAddress;
    uint256 lastClaimTime;
    uint256 nextClaimTime;
    uint256 totalClaims;
    uint256 totalClaimedAmount;
    
    }

    event Claimed (
    uint256 amountClaimed,
    address user
    );

    Claims[] public claimsArray;
    uint public claimCount;
    mapping (address => ClaimInfo) public userClaimInfo;
    mapping (address => bool) public claimed;
    address public constant DIRECTOR1_WALLET_ADDRESS = 0x15c72f29B3cE6f0cBf8778E0Dd6f43736259b1bC;
    address public constant DIRECTOR2_WALLET_ADDRESS = 0x1F0B9a481e4835E0E6e3545D5804D3997C626bD0;



    constructor(address _pintTokenAddress){
        claimCount = 0;
        pintToken = IERC20(_pintTokenAddress);
    }

    // function checkClaimStatus(address user) public view returns (bool) {
    //     return userClaimInfo[user].hasClaimed;
    // }

    function checkClaimStatus(address user) public view returns (bool) {
        return claimed[user];
    }    

    function recoverUnclaimed(uint256 _amount) public{
    require(msg.sender == DIRECTOR1_WALLET_ADDRESS || msg.sender == DIRECTOR2_WALLET_ADDRESS, "Only admin can recover unclaimed tokens");
    require(pintToken.transfer(msg.sender, _amount), "Recovery failed");
    }

    function claim(uint256  _amount, uint256 _previousClaimAmount, bool _hasClaimedBefore) public  {
        if(_hasClaimedBefore == true){
           claimed[msg.sender] = true;
            if(userClaimInfo[msg.sender].nextClaimTime == 0){
                 require(pintToken.transfer(msg.sender, _amount), "Claim failed");
                 ClaimInfo memory _claimInfo = ClaimInfo(msg.sender, block.timestamp, block.timestamp + 7 days, 2, _previousClaimAmount + _amount );
                    userClaimInfo[msg.sender] = _claimInfo;
                claimCount++;
                emit Claimed(_amount, msg.sender);
                }
                else {
                 require(pintToken.transfer(msg.sender, _amount), "Claim failed");
                 ClaimInfo memory _claimInfo = ClaimInfo(msg.sender, block.timestamp, block.timestamp + 7 days, userClaimInfo[msg.sender].totalClaims + 1, userClaimInfo[msg.sender].totalClaimedAmount + _amount );
                    userClaimInfo[msg.sender] = _claimInfo;
                claimCount++;
                emit Claimed(_amount, msg.sender);
            }
        } 
        else {
                require(pintToken.transfer(msg.sender, _amount), "Claim failed");
                claimed[msg.sender] = true;
                ClaimInfo memory _claimInfo = ClaimInfo(msg.sender, block.timestamp, block.timestamp + 7 days, 1,  _amount );
                    userClaimInfo[msg.sender] = _claimInfo;
                claimCount++;
                emit Claimed(_amount, msg.sender);

        }
    }
}


