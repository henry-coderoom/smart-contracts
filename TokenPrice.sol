// SPDX-License-Identifier: GPL-3.0
import "@openzeppelin/contracts/utils/Strings.sol";
pragma solidity >=0.7.0 <0.9.0;

   interface IPancakeRouter02 {

   function getAmountsIn(uint amountOut, address[] memory path) external view returns (uint[] memory amounts);
   function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
   function WETH() external view returns (address);
   
    }
    //0x10ed43c718714eb63d5aa57b78b54704e256024e 
    
   contract TokenPrice {
        IPancakeRouter02 private _pancakeRouter;
   address public busdContractAddress = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56; //0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56
   constructor(IPancakeRouter02 routerAddress){
       _pancakeRouter = routerAddress;
   }
       function getTokenPriceUsd(address theToken, uint256 amount) public view returns(uint256) {
       address[] memory path = new address[](3);
       path[0] = theToken;
       path[1] = address(_pancakeRouter.WETH());
       path[2] = busdContractAddress;
       uint256[] memory amounts = _pancakeRouter.getAmountsOut(amount, path);
       return amounts[2];
    }

    function getBNBPriceUsd(uint256 amount) public view returns(uint256) {
       address[] memory path = new address[](2);
       path[0] = address(_pancakeRouter.WETH());
       path[1] = busdContractAddress;
       uint256[] memory amounts = _pancakeRouter.getAmountsOut(amount, path);
       return amounts[1];
    }
   }