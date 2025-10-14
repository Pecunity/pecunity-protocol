// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract PecunityToken is ERC20, ERC20Burnable, ERC20Permit {
    constructor(
        address recipient,
        uint256 maxSupply
    ) ERC20("Pecunity Token", "PEC") ERC20Permit("Pecunity Token") {
        _mint(recipient, maxSupply);
    }
}
