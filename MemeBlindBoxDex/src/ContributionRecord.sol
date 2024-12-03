// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract ContributionRecord {

    uint256[] public contributeBlock; // Record all blocks with contributions
    uint256 public lastContributionBlock;
    struct BlockContributeInfo {
        uint256 index;
        address[] users;
        mapping (address => uint256) balanceOf;
        uint256 nextBlock;
        uint256 accumulateContributionCount; // Contribution count.
        uint256 accumulateContributionValue; // Total Contribute amount.
    }
    mapping (uint256 => BlockContributeInfo) public contributeBlockInfo; // Track contributions and users for each block
    bool public isContributeAllowed = true;

    event Contribute(address indexed user, uint256 indexed blockNumber, uint256 value);

    function contribute() payable public {
        uint256 currentBlock = block.number;
        require(msg.value > 0, "Contribution amount must be greater than 0");

        if (lastContributionBlock != currentBlock) {
            contributeBlockInfo[currentBlock].accumulateContributionValue = msg.value + contributeBlockInfo[lastContributionBlock].accumulateContributionValue;
            contributeBlockInfo[currentBlock].accumulateContributionCount = 1 + contributeBlockInfo[lastContributionBlock].accumulateContributionCount;
            contributeBlockInfo[lastContributionBlock].nextBlock = currentBlock;
            lastContributionBlock = currentBlock;
            contributeBlock.push(currentBlock);
        } else {
            contributeBlockInfo[currentBlock].accumulateContributionValue += msg.value;
            contributeBlockInfo[currentBlock].accumulateContributionCount++;
        }

        // If it is the first contribute in the current block height, add it to the block array.
        if (contributeBlockInfo[currentBlock].balanceOf[msg.sender] == 0) {
            contributeBlockInfo[currentBlock].users.push(msg.sender);
        }

        // Accumulate the contribute value.
        contributeBlockInfo[currentBlock].balanceOf[msg.sender] += msg.value;
        emit Contribute(msg.sender, currentBlock, msg.value);
    }

    function getBlockUsersLength(uint256 blockNumber) public view returns (uint256) {
        return contributeBlockInfo[blockNumber].users.length;
    }

    function getBlockUsers(uint256 blockNumber, uint256 startIndex, uint256 endIndex) public view returns (address[] memory) {
        uint256 length = contributeBlockInfo[blockNumber].users.length;
        require(endIndex <= startIndex && startIndex <= length - 1, "EndIndex must be greater than or equal to startIndex");
        if (endIndex > length -1) {
            endIndex = length -1;
        }
        address[] memory balanceArray = new address[](endIndex - startIndex + 1);
        for (uint i = startIndex; i <= endIndex; i++) {
            balanceArray[i - startIndex] = contributeBlockInfo[blockNumber].users[i];
        }
        return balanceArray;
    }

    function getUserContributionFromBlock(uint256 blockNumber, address user) public view returns (uint256) {
        return contributeBlockInfo[blockNumber].balanceOf[user];
    }

    function getNextBlock(uint256 blockNumber) public view returns (uint256) {
        return contributeBlockInfo[blockNumber].nextBlock;
    }

    // Get the number of blocks with contributions
    function getContributionBlockLength() public view returns (uint256) {
        return contributeBlock.length;
    }

    function getContributionBlockIndex(uint256 blockNumber) public view returns (uint256) {
        return contributeBlockInfo[blockNumber].index;
    }

    function batchGetContributionBlockNumber(uint256 startIndex, uint256 endIndex) external view returns (uint256[] memory) {
        require(startIndex <= endIndex && startIndex <= contributeBlock.length - 1, "EndIndex must be greater than or equal to startIndex");
        if (endIndex > contributeBlock.length - 1) {
            endIndex = contributeBlock.length - 1;
        }
        uint256[] memory blockNumbers = new uint256[](endIndex - startIndex + 1);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            blockNumbers[i - startIndex] = contributeBlock[i];
        }
        return blockNumbers;
    }

    function _setContributeAllowed(bool _isContributeAllowed) internal {
        isContributeAllowed = _isContributeAllowed;
    }

    // Receive ETH
    receive() external payable {
        require(isContributeAllowed, "Contribute is not allowed");
        contribute();
    }
}