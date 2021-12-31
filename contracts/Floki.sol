// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract FLOKI is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    address payable public marketingAddress = payable(0x2b9d5c7f2EAD1A221d771Fb6bb5E35Df04D60AB0); // Marketing Address
    mapping(address => uint256) private _rOwned;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private _isExcludedFromFee;

    string private _name = "FLOKI";
    string private _symbol = "FLOKI";
    uint8 private _decimals = 9;

    uint256 public _liquidityFee = 4;
    uint256 private _previousLiquidityFee = _liquidityFee;

    uint256 private _feeRate = 4;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    bool inSwapAndLiquify;

    bool tradingOpen = false;

    event SwapETHForTokens(uint256 amountIn, address[] path);

    event SwapTokensForETH(uint256 amountIn, address[] path);

    event UpdatedLiquidityFee(uint256 oldiquidityFee, uint256 newLiquidityFee);
    event UpdatedFeeRate(uint256 oldFeeRate, uint256 newFeeRate);
    event UpdatedMarketingAddress(address oldAddress, address newAddress);

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor() {
        _rOwned[_msgSender()] = totalSupply();

        emit Transfer(address(0), _msgSender(), totalSupply());
    }

    function initContract() external onlyOwner {
        // PancakeSwap: 0x10ED43C718714eb63d5aA57B78B54704E256024E
        // Uniswap V2: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
            address(this),
            _uniswapV2Router.WETH()
        );

        uniswapV2Router = _uniswapV2Router;

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
    }

    function openTrading() external onlyOwner {
        tradingOpen = true;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        // Ten trillion, i.e., 10,000,000,000,000 tokens.
        return 1e13 * 1e9;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _rOwned[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance")
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero")
        );
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

        // buy
        if (from == uniswapV2Pair && to != address(uniswapV2Router) && !_isExcludedFromFee[to]) {
            require(tradingOpen, "Trading not yet enabled.");
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        //sell

        if (!inSwapAndLiquify && tradingOpen && to == uniswapV2Pair) {
            if (contractTokenBalance > 0) {
                if (contractTokenBalance > balanceOf(uniswapV2Pair).mul(_feeRate).div(100)) {
                    contractTokenBalance = balanceOf(uniswapV2Pair).mul(_feeRate).div(100);
                }
                swapTokens(contractTokenBalance);
            }
        }

        bool takeFee = false;

        //take fee only on swaps
        if ((from == uniswapV2Pair || to == uniswapV2Pair) && !(_isExcludedFromFee[from] || _isExcludedFromFee[to])) {
            takeFee = true;
        }

        _tokenTransfer(from, to, amount, takeFee);
    }

    function swapTokens(uint256 contractTokenBalance) private lockTheSwap {
        swapTokensForEth(contractTokenBalance);

        //Send to Marketing address
        uint256 contractETHBalance = address(this).balance;
        if (contractETHBalance > 0) {
            sendETHToMarketing(address(this).balance);
        }
    }

    function sendETHToMarketing(uint256 amount) private {
        // Ignore the boolean return value. If it gets stuck, then retrieve via `emergencyWithdraw`.
        marketingAddress.call{ value: amount }("");
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this), // The contract
            block.timestamp
        );

        emit SwapTokensForETH(tokenAmount, path);
    }

    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        if (!takeFee) {
            removeAllFee();
        }

        _transferStandard(sender, recipient, amount);

        if (!takeFee) {
            restoreAllFee();
        }
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        uint256 tax = (amount * _liquidityFee) / 100;
        uint256 taxedAmount = amount - tax;

        _rOwned[sender] -= taxedAmount;
        _rOwned[recipient] += taxedAmount;

        emit Transfer(sender, recipient, taxedAmount);
    }

    function removeAllFee() private {
        if (_liquidityFee == 0) return;

        _previousLiquidityFee = _liquidityFee;
        _liquidityFee = 0;
    }

    function restoreAllFee() private {
        _liquidityFee = _previousLiquidityFee;
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner {
        uint256 _oldLiquidityFee = _liquidityFee;

        _liquidityFee = liquidityFee;

        emit UpdatedLiquidityFee(_oldLiquidityFee, liquidityFee);
    }

    function setMarketingAddress(address _marketingAddress) external onlyOwner {
        require(_marketingAddress != address(0), "FLOKI: Invalid marketing address");

        address _oldMarketingAddress = marketingAddress;

        marketingAddress = payable(_marketingAddress);

        emit UpdatedMarketingAddress(_oldMarketingAddress, marketingAddress);
    }

    function transferToAddressETH(address payable recipient, uint256 amount) private {
        recipient.transfer(amount);
    }

    function setFeeRate(uint256 rate) external onlyOwner {
        uint256 _oldRate = _feeRate;

        _feeRate = rate;

        emit UpdatedFeeRate(_oldRate, rate);
    }

    //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}

    // Withdraw ETH that gets stuck in contract by accident
    function emergencyWithdraw() external onlyOwner {
        payable(owner()).send(address(this).balance);
    }
}
