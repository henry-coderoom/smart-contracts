// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract OffyMigrator{

address private feeCollectorAddress;
IERC20 newOffy;
IERC20 oldOffy;

struct Migrations{
    address migratorAddress;
    uint256 migratedAmount;
    uint256 migrationTime;
    bytes32 hash;
}

event Migrated (
    uint256 amountMigrated,
    address user
);

Migrations[] public migrationsArray;
uint public migrationCount;


    constructor(address _feeCollectorAddress, address _newOffy){
        migrationCount = 0;
        feeCollectorAddress = _feeCollectorAddress;
        newOffy = IERC20(_newOffy);

    }

    function migrate(uint256  _amount, uint256  _fee, address  _oldOffyAddress) public  {
        oldOffy = IERC20(_oldOffyAddress);
        uint256 _amountAfterFee = _amount - _fee;
        require(oldOffy.transferFrom(msg.sender, address(this), _amount ), "Migration failed or canceled");
        require(newOffy.transfer(msg.sender, _amountAfterFee), "Migration failed");
        require(newOffy.transfer(feeCollectorAddress, _fee), "Migration failed");

        Migrations memory _migrations = Migrations(msg.sender, _amount, block.timestamp, block.blockhash);
        migrationsArray.push(_migrations);
        migrationCount++;
        emit Migrated(_amount, msg.sender);
    }
}


