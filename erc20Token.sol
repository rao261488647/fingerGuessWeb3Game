// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;  //solidity编译版本声明

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";  //第三方文件引入

//合约声明
contract DemoToken is ERC20 {
    address owner; //地址变量
    uint256 total = 5000000 * 10**18; //数字变量

    //构造器
    constructor() ERC20("Pig", "PP") {
        owner = msg.sender;
        _mint(msg.sender, total);
    }

    //方法
    function getTotal() public view onlyOwner returns (uint256) {
        return total;
    }

    //修饰符
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
}
