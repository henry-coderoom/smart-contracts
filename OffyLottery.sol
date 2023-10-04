// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface IPancakeRouter02 {
   function getAmountsIn(uint amountOut, address[] memory path) external view returns (uint[] memory amounts);
   function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
   function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
   function WETH() external view returns (address);

   function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external returns (uint256[] memory amounts);
   function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable returns (uint256[] memory amounts); 
}

contract OffyLottery {
    address public prizePoolTokenAddress;
    address public ADMIN1_ADDRESS = 0x15c72f29B3cE6f0cBf8778E0Dd6f43736259b1bC;
    address public ADMIN2_ADDRESS = 0x1F0B9a481e4835E0E6e3545D5804D3997C626bD0;
    address public AIRDROP_CLAIM_TOOL_ADDRESS = 0xf8e74D9e474FE3641E2b0eF0B602fB606B779155;
    address private constant busdContractAddress = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56; //0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee

    uint256 private constant JACKPOT_PERCENTAGE = 6000; //60%
    uint256 private constant WINNERS_PERCENTAGE = 2500; //25%
    uint256 private constant ROLLOVER_PERCENTAGE = 1000; //10%
    
    uint256 private constant DEV_TAX = 450; //4.5%
    uint256 private constant PINT_CLAIM_TOOL_TAX = 50; //0.5%

    uint256 public maxNumberTicketsPerBuy = 100;
    uint256 public currentPoolId;
    uint256 public nextTicketId = 1;
    uint256 public nextRolloverAmount;
    uint256 public totalTicketsCount;

    IERC20 private _prizePoolToken;
    IPancakeRouter02 private _pancakeRouter;


    enum Status {
        Pending,
        Open,
        Close
    }

    struct Pool {
        Status status;
        uint256 startTime;
        uint256 endTime;
        uint256 totalPrizePool;
        uint256 injectedAmount;
        uint256 totalEntries;
        bool jackpotDrawn;
    }

    // Mapping are cheaper than arrays
    mapping(uint256 => Pool) public pools;
    
    //keeps track of winning ticket ids to ticketNumbers for a particular pool
    mapping(uint256 => mapping(uint256 => uint256)) public winningTicketNumbersPerPoolId;

    mapping(uint256 => uint256[]) public winningTicketIdsForPoolId;

    //keeps track of ticket ids to ticket number for a particular pool
    mapping(uint256 => mapping(uint256 => uint256)) public ticketEntriesPerPoolId;

    //Keeps track of ticket number to addresses of ticketOwners per poolId
    mapping(uint256 => mapping(uint256 => address[])) private _ticketNumberOwners;
 
    //Keeps track of unique pool participants
    mapping(uint256 => address[]) private _participants;

    // Keep track of user ticket numbers for a given poolId
    mapping(address => mapping(uint256 => uint256[])) private _userTicketIdsPerPoolId;


    event PoolClose(uint256 indexed poolId);
    event PoolInjection(uint256 indexed poolId, uint256 injectedAmount);
    event PoolOpen(
        uint256 indexed poolId,
        uint256 startTime,
        uint256 endTime,
        uint256 injectedAmount
    );
    event TicketsPurchase(address indexed buyer, uint256 indexed poolId, uint256 numberTickets);
    event PoolNumberDrawn(uint256 indexed poolId);



   constructor(IPancakeRouter02 pancakeRouter, address _prizePoolTokenAddress) {
       prizePoolTokenAddress = _prizePoolTokenAddress;
       _prizePoolToken = IERC20(prizePoolTokenAddress);
       _pancakeRouter = pancakeRouter;
   }


    function startPool(uint256 _injectionAmount, uint256 _endTime) external onlyOwner {
        require(
            (currentPoolId == 0) || (pools[currentPoolId].status == Status.Close),
            "Not yet time to start new pool");

        require(_prizePoolToken.allowance(msg.sender, address(this)) >= _injectionAmount, "Approve injection funds first");
        require(_prizePoolToken.transferFrom(msg.sender, address(this), _injectionAmount), "Initial pool funds must be deposited first");

        currentPoolId++;

        pools[currentPoolId] = Pool({
            status: Status.Open,
            startTime: block.timestamp,
            endTime: block.timestamp + _endTime,
            totalPrizePool: _injectionAmount,
            injectedAmount: _injectionAmount,
            totalEntries: 0,
            jackpotDrawn: false
        });

        emit PoolOpen(currentPoolId, block.timestamp, block.timestamp + _endTime, _injectionAmount
    );
    }

    function buyTicketsWithToken (uint256 amountIn, address paymentTokenAddress, uint256[] memory ticketNumbers) public {
       address[] memory path = new address[](3);
       path[0] = paymentTokenAddress; // The payment token is the token sent by the user
       path[1] = address(_pancakeRouter.WETH());
       path[2] = prizePoolTokenAddress;

       uint256[] memory amounts = _pancakeRouter.getAmountsOut(amountIn, path);
       require(amounts[0] > 0 && amounts[1] > 0 && amounts[2] > 0, "No liquidity");

       // Transfer paymentTokenAddress token to contract
       IERC20(paymentTokenAddress).transferFrom(msg.sender, address(this), amounts[0]);
       // Swap paymentTokenAddress for Pint
       _approveSpend(paymentTokenAddress);
       _pancakeRouter.swapExactTokensForTokens(
           amounts[0],
           amounts[2],
           path,
           address(this),
           block.timestamp + 3600
       );

        _mintTickets(ticketNumbers, amounts[2]);
    }
    

    function buyTicketsWithBNB(uint256[] memory ticketNumbers) public payable {
       address[] memory path = new address[](2);
       path[0] = address(_pancakeRouter.WETH());
       path[1] = prizePoolTokenAddress;

       uint256[] memory amounts = _pancakeRouter.getAmountsOut(msg.value, path);
       require(amounts[0] > 0 && amounts[1] > 0, "No liquidity for this token");
       _pancakeRouter.swapExactETHForTokens{value: msg.value}(
           amounts[1],
           path,
           address(this),
           block.timestamp + 3600
       );        
        
        _mintTickets(ticketNumbers, amounts[1]);

    }

    function buyTicketsWithPint(uint256 _amount, uint256[] memory ticketNumbers) public {

        _prizePoolToken.transferFrom(msg.sender, address(this), _amount);
        _mintTickets(ticketNumbers, _amount);
        
    }


   function _mintTickets(uint256[] memory ticketNumbers, uint256 _amount ) private {
       require(pools[currentPoolId].status == Status.Open, "Pool is not open");
       require(pools[currentPoolId].endTime > block.timestamp, "Entry time for this pool has pass");
       require(ticketNumbers.length != 0, "No ticket specified");
       require(ticketNumbers.length <= maxNumberTicketsPerBuy, "Too many tickets");

       if(_userTicketIdsPerPoolId[msg.sender][currentPoolId].length < 1){
            _participants[currentPoolId].push(msg.sender);
       }

       // Mint tickets
       for(uint256 i = 0; i < ticketNumbers.length; i ++){
        _userTicketIdsPerPoolId[msg.sender][currentPoolId].push(ticketNumbers[i]);
        ticketEntriesPerPoolId[currentPoolId][nextTicketId] = ticketNumbers[i];
        _ticketNumberOwners[currentPoolId][ticketNumbers[i]].push(msg.sender);
        pools[currentPoolId].totalEntries += 1;
        nextTicketId++;        
        totalTicketsCount++;

       }

        pools[currentPoolId].totalPrizePool += _amount;
        emit TicketsPurchase(msg.sender, currentPoolId, ticketNumbers.length);


   }


   function drawWinners(uint256 _poolId) external onlyOwner {
       Pool memory currentPool = pools[_poolId];
       require(currentPoolId != 0, "No active pool");
       require(currentPool.status == Status.Open, "You can only draw winners for active pool");
       require(block.timestamp > currentPool.endTime, "This pool end-time has not reached");
       
       if(currentPool.totalEntries == 0){
            uint256 injectionAmountForNextPool = (currentPool.totalPrizePool * ROLLOVER_PERCENTAGE) / 10000;
            uint256 leftOverFunds = currentPool.totalPrizePool - injectionAmountForNextPool;
            nextRolloverAmount = injectionAmountForNextPool;

            _prizePoolToken.transfer(ADMIN2_ADDRESS, injectionAmountForNextPool);
            _prizePoolToken.transfer(ADMIN1_ADDRESS, leftOverFunds);
            pools[currentPoolId].status = Status.Close;
            pools[currentPoolId].jackpotDrawn = true;
            emit PoolClose(_poolId);


       } else if(currentPool.totalEntries <= 5) {
            winningTicketIdsForPoolId[currentPoolId] = _generateRandomListOfWinners(1, _poolId); 
       } else if(currentPool.totalEntries <= 19) {
            winningTicketIdsForPoolId[currentPoolId] = _generateRandomListOfWinners(3, _poolId);   
        } else if(currentPool.totalEntries <= 49) {
            winningTicketIdsForPoolId[currentPoolId] = _generateRandomListOfWinners(6, _poolId);
       }else if(currentPool.totalEntries <= 99) {
            winningTicketIdsForPoolId[currentPoolId] = _generateRandomListOfWinners(10, _poolId);
       } else if(currentPool.totalEntries <= 149) {
            winningTicketIdsForPoolId[currentPoolId] = _generateRandomListOfWinners(15, _poolId);
       } else if(currentPool.totalEntries <= 199) {
            winningTicketIdsForPoolId[currentPoolId] = _generateRandomListOfWinners(20, _poolId);
       } else {
            winningTicketIdsForPoolId[currentPoolId] = _generateRandomListOfWinners(25, _poolId);
       }
        nextTicketId = 1;
        emit PoolNumberDrawn(_poolId);
   }


   function distributeJackpotAndTaxes(uint256 _poolId) external onlyOwner {
       require(pools[_poolId].status == Status.Pending, "Distribution not available for this pool");
       Pool memory currentPool = pools[_poolId];
       uint256 jackpotAmount = (currentPool.totalPrizePool * JACKPOT_PERCENTAGE) / 10000;
       uint256 injectionAmountForNextPool = (currentPool.totalPrizePool * ROLLOVER_PERCENTAGE) / 10000;
       
       //Move injectionAmountForNextPool to admin account and update rollOverAmount
        _prizePoolToken.transfer(ADMIN2_ADDRESS, injectionAmountForNextPool);
        nextRolloverAmount = injectionAmountForNextPool;
       
        // Transfer dev tax to dev address
       uint256 devTax = (currentPool.totalPrizePool * DEV_TAX) / 10000;
       _prizePoolToken.transfer(ADMIN1_ADDRESS, devTax);

       // Transfer PINT claim tool tax to PINT claim tool address
       uint256 pintClaimToolTax = (currentPool.totalPrizePool * PINT_CLAIM_TOOL_TAX) / 10000;
       _prizePoolToken.transfer(AIRDROP_CLAIM_TOOL_ADDRESS, pintClaimToolTax);

       // Distribute to jackpot winner or winners
       uint256 jackpotWinnerIndex = winningTicketIdsForPoolId[_poolId][0];
       uint256 winningTicketNum = ticketEntriesPerPoolId[currentPoolId][jackpotWinnerIndex];

       address[] memory jackpotWinnerAddresses = _ticketNumberOwners[_poolId][winningTicketNum];
       uint256 amountPerWinning = jackpotAmount / jackpotWinnerAddresses.length;

       for(uint256 i = 0; i < jackpotWinnerAddresses.length; i++) {
       require( _prizePoolToken.transfer(jackpotWinnerAddresses[i], amountPerWinning), "Jackpot transfer failed");
       }      

       winningTicketNumbersPerPoolId[currentPoolId][jackpotWinnerIndex] = ticketEntriesPerPoolId[currentPoolId][jackpotWinnerIndex];
       pools[_poolId].jackpotDrawn = true;

       if(winningTicketIdsForPoolId[_poolId].length == 1) {
         uint256 winnersAmount = (pools[_poolId].totalPrizePool * WINNERS_PERCENTAGE) / 10000;
         //Add other winnersAmount to injectionAmountForNextPool, send to admin account and update rollOverAmount
         _prizePoolToken.transfer(ADMIN2_ADDRESS, winnersAmount);
         pools[currentPoolId].status = Status.Close;
         emit PoolClose(_poolId);

       }
   }



    function distributeOtherWinners(uint256 _poolId) external onlyOwner {
        require(pools[_poolId].jackpotDrawn == true, "Distribute jackpot and taxes first");
        require(pools[_poolId].status == Status.Pending, "Other Winners' Distribution not available for this pool");

        uint256 winnersAmount = (pools[currentPoolId].totalPrizePool * WINNERS_PERCENTAGE) / 10000;
        uint256 prizePerWinningId = winnersAmount / (winningTicketIdsForPoolId[_poolId].length - 1);
       
        for (uint256 i = 1; i <= winningTicketIdsForPoolId[_poolId].length - 1; i++) {
            uint256 winningTicketNum = ticketEntriesPerPoolId[currentPoolId][winningTicketIdsForPoolId[_poolId][i]];
                
            address[] memory winnerAddresses = _ticketNumberOwners[_poolId][winningTicketNum];
            uint256 amountPerWinning = prizePerWinningId / winnerAddresses.length;
            for(uint256 e = 0; e < winnerAddresses.length; e++) {
            require(_prizePoolToken.transfer(winnerAddresses[e], amountPerWinning), "Winner prize transfer failed");
                }
            winningTicketNumbersPerPoolId[currentPoolId][winningTicketIdsForPoolId[_poolId][i]] = ticketEntriesPerPoolId[currentPoolId][winningTicketIdsForPoolId[_poolId][i]];
        }

        pools[currentPoolId].status = Status.Close;
        emit PoolClose(_poolId);

    }

    
    function _generateRandomListOfWinners(uint256 numWinners, uint256 _poolId) internal returns(uint256[] memory) {
        uint256[] memory winnersList = new uint256[](numWinners);
        uint256 index = 0;
        while (index < numWinners) {
            uint256 winnerIndex = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, index, _participants[_poolId]))) % pools[_poolId].totalEntries + 1;
            bool isUnique = true;
            for (uint256 i = 0; i < index; i++) {
                if (winnersList[i] == winnerIndex) {
                    isUnique = false;
                        break;
                }
            }
            if (isUnique) {
                    winnersList[index] = winnerIndex;
                    index++;
            }
        }
        pools[_poolId].status = Status.Pending;
        return winnersList;
    }

    function injectFundsForCurrentPool(uint256 _amount, uint256 _poolId) external onlyOwner {
        require(pools[_poolId].status == Status.Open, "Pool is not open");
        require(pools[_poolId].endTime > block.timestamp, "Pool has ended");
        _prizePoolToken.transferFrom(msg.sender, address(this), _amount);
        pools[_poolId].totalPrizePool += _amount;
        pools[_poolId].injectedAmount += _amount;

        emit PoolInjection(_poolId, _amount);

    }

   function getParticipantsForPoolId(uint256 _poolId) public view returns (address[] memory) {
       uint256 _length = _participants[_poolId].length;
       address[] memory participants = new address[](_length);
       for(uint256 i = 0; i < _length; i++){
           participants[i] = _participants[_poolId][i];
       }
        return participants;
    }

    function getUserTicketNumbersForPoolId(address _user, uint256 _poolId) public view returns (uint256[] memory, uint256) {
        uint256 _length = _userTicketIdsPerPoolId[_user][_poolId].length;
       uint256[] memory tickets = new uint256[](_length);
       for(uint256 i = 0; i < _length; i++){
           tickets[i] = _userTicketIdsPerPoolId[_user][_poolId][i];
       }
        return (tickets, pools[_poolId].endTime);
            }

    function getWinningTicketNumbersForPoolId(uint256 _poolId) public view returns(uint256[] memory){
        // require(pools[_poolId].status == Status.Close, "Pool is not yet closed or drawn");
        uint256[] memory winnerTicketIds = winningTicketIdsForPoolId[_poolId];
        uint256[] memory winningTicketNumbers = new uint256[](winnerTicketIds.length);
        for(uint256 i = 0; i < winnerTicketIds.length; i++) {
            winningTicketNumbers[i] = ticketEntriesPerPoolId[_poolId][winnerTicketIds[i]];
        }
        return winningTicketNumbers;
    }
    function getNumberOfWinnersPerTicketNumber(uint256 _ticketNumber, uint256 _poolId) public view returns(uint256){
        return _ticketNumberOwners[_poolId][_ticketNumber].length;
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


    function recoverBNB(address payable recipient, uint256 amount) external onlyOwner {
      recipient.transfer(amount);
   }

    function recoverTokens(address token, uint256 amount)  external onlyOwner {
      IERC20 t = IERC20(token);
      t.transfer(msg.sender, amount);
   }

    function getContractBnbBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getContractTokenBalance(address token) public view returns (uint256) {
        IERC20 t = IERC20(token);
        return t.balanceOf(address(this));
    }

    function _approveSpend(address token) private {
       IERC20 t = IERC20(token);
       uint256 currentAllowance = t.allowance(address(this), address(_pancakeRouter));
       if (currentAllowance < type(uint256).max) {
           t.approve(address(_pancakeRouter), type(uint256).max);
       }
   }


    function changePrizePoolToken(address _newPrizePoolToken) external onlyOwner
    {   
       prizePoolTokenAddress = _newPrizePoolToken;
       _prizePoolToken = IERC20(prizePoolTokenAddress); 
    }

    function changeAdmin2Address(address _newAddress) external onlyOwner 
    { ADMIN2_ADDRESS = _newAddress; }

    function changeAdmin1Address(address _newAddress) external onlyOwner
    { ADMIN1_ADDRESS = _newAddress;}
    
    function changeClaimToolAddress(address _newAddress) external onlyOwner
    {   AIRDROP_CLAIM_TOOL_ADDRESS = _newAddress;}


    modifier onlyOwner() {
        require(msg.sender == ADMIN1_ADDRESS || msg.sender == ADMIN2_ADDRESS, "Only admins can perform this action");
        _;
    }
}