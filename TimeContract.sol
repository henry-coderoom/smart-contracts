// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract TimeContract{

    function getTime(uint256 _ageInSeconds) public view returns (uint256)
    {   
        return block.timestamp + _ageInSeconds; 
    }

}