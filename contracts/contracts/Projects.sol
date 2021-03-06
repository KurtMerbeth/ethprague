// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Projects is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    EnumerableSet.Bytes32Set private projectList; // just as a work around

    IERC20 public token;
    
    mapping(address => uint256) public nonces;
    mapping(bytes32 => Project) public projects;
    mapping(bytes32 => uint256) public funds;
    
    uint256 public reservedFunds;

    struct Project {
        bytes32 id;
        address owner;
        string ipfs;
        uint256 startDate;
        uint256 endDate;
    }

    constructor(IERC20 _token) {
        token = _token;
    }

    modifier onlyMember(address _account) {
        require(token.balanceOf(_account) >= 1 ether);
        _;
    }

    function addProject(string memory _ipfs, uint256 _endDate)
        external
        onlyMember(msg.sender)
    {
        nonces[msg.sender]++;
        Project memory project;
        project.id = keccak256(
            abi.encodePacked(msg.sender, nonces[msg.sender])
        );
        project.owner = msg.sender;
        project.ipfs = _ipfs;
        project.startDate = block.timestamp;
        project.endDate = _endDate;

        projects[project.id] = project;
        projectList.add(project.id);

        emit ProjectAdded(
            project.id,
            project.owner,
            project.ipfs,
            project.startDate,
            project.endDate
        );
    }

    function addFunds(bytes32 _project, uint256 _amount)
        external
        onlyOwner
        nonReentrant
    {
        require(projects[_project].endDate >= block.timestamp, "Project ended");
        reservedFunds += _amount;
        funds[_project] += _amount;
        require(
            reservedFunds <= address(this).balance,
            "Contract balance too low"
        );
        emit FundsAdded(_project, _amount);
    }

    function withdrawFunds(bytes32 _project) external nonReentrant {
        uint256 fundAmount = funds[_project];
        address projectOwner = projects[_project].owner;
        funds[_project] = 0;
        require(
            projectOwner == msg.sender,
            "Only project owner can withdraw funds"
        );
        require(fundAmount > 0, "No funds to withdraw");
        require(
            address(this).balance >= fundAmount,
            "Contract balance too low"
        );
        reservedFunds -= fundAmount;
        (bool success, ) = projectOwner.call{value: fundAmount}("");
        require(success, "Transfer failed.");
        emit FundsWithdrawn(_project, fundAmount);
    }

    function endProject(bytes32 _project) external onlyOwner {
        require(
            projects[_project].endDate >= block.timestamp,
            "Project already ended"
        );
        projects[_project].endDate = block.timestamp;
        uint256 fundAmount = funds[_project];
        if (fundAmount > 0) {
            funds[_project] = 0;
            reservedFunds -= fundAmount;
        }
        emit ProjectEnded(_project);
    }

    function updateEndDate(bytes32 _project, uint256 _endDate)
        external
        onlyOwner
        nonReentrant
    {
        require(_endDate >= block.timestamp, "End date must be in the future");
        projects[_project].endDate = _endDate;
        emit ProjectEndDateUpdated(_project, _endDate);
    }

    function withdrawEther(address _to) external onlyOwner {
        (bool success, ) = _to.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

    function getProjects() external view returns (bytes32[] memory) {
        bytes32[] memory result = new bytes32[](projectList.length());

        for(uint256 i = 0; i < projectList.length(); i++) {
            result[i] = projectList.at(i);
        }
        return result;
    }

    function getProjectLength() external view returns(uint256) {
        return projectList.length();
    }

    function getProjectAt(uint256 i) external view returns(bytes32) {
        return projectList.at(i);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    event Received(address, uint);
    event ProjectAdded(
        bytes32 indexed id,
        address indexed owner,
        string ipfs,
        uint256 startDate,
        uint256 endDate
    );
    event FundsAdded(bytes32 indexed project, uint256 amount);
    event FundsWithdrawn(bytes32 indexed project, uint256 amount);
    event ProjectEnded(bytes32 indexed project);
    event ProjectEndDateUpdated(bytes32 indexed project, uint256 endDate);
}
