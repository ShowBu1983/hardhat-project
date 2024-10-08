// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0; 
import "@openzeppelin/contracts/token/ERC20/ERC20.sol"; 

contract TokenRCC is ERC20 { 
    uint8 public dec = 18;

    event LogNewAlert(string description, address indexed _from, uint256 _n);

    constructor(uint256 initialSupply) ERC20("RemoteCodeCamp", "RCC") {
        uint256 totalSupply = initialSupply * 10 ** uint256(dec);
        _mint(msg.sender, totalSupply); 
    } 

    function _reward() public { 
        _mint(msg.sender, 10 ** uint256(dec)); 
        emit LogNewAlert('_rewarded', msg.sender, block.number); 
    } 
} 