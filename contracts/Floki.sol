// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./tax/ITaxHandler.sol";
import "./treasury/ITreasuryHandler.sol";

contract FLOKI is IERC20, Ownable {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    ITaxHandler public taxHandler;
    ITreasuryHandler public treasuryHandler;

    constructor(address taxHandlerAddress, address treasuryHandlerAddress) {
        taxHandler = ITaxHandler(taxHandlerAddress);
        treasuryHandler = ITreasuryHandler(treasuryHandlerAddress);

        _balances[_msgSender()] = totalSupply();

        emit Transfer(address(0), _msgSender(), totalSupply());
    }

    function name() external pure returns (string memory) {
        return "FLOKI";
    }

    function symbol() external pure returns (string memory) {
        return "FLOKI";
    }

    function decimals() external pure returns (uint8) {
        return 9;
    }

    function totalSupply() public pure override returns (uint256) {
        // Ten trillion, i.e., 10,000,000,000,000 tokens.
        return 1e13 * 1e9;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        treasuryHandler.beforeTransferHandler(from, to, amount);

        uint256 tax = taxHandler.getTax(from, to, amount);
        uint256 taxedAmount = amount - tax;

        _balances[from] -= amount;
        _balances[to] += taxedAmount;

        if (tax > 0) {
            _balances[address(treasuryHandler)] += tax;

            emit Transfer(from, address(this), tax);
        }

        treasuryHandler.afterTransferHandler(from, to, amount);

        emit Transfer(from, to, taxedAmount);
    }
}
