// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./governance/IGovernanceToken.sol";
import "./tax/ITaxHandler.sol";
import "./treasury/ITreasuryHandler.sol";

contract FLOKI is IERC20, IGovernanceToken, Ownable {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => address) public delegates;
    mapping(address => uint256) public nonces;
    mapping(address => uint32) public numCheckpoints;
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    /// @notice The EIP-712 typehash for the contract's domain.
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract.
    bytes32 public constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    ITaxHandler public taxHandler;
    ITreasuryHandler public treasuryHandler;

    constructor(address taxHandlerAddress, address treasuryHandlerAddress) {
        taxHandler = ITaxHandler(taxHandlerAddress);
        treasuryHandler = ITreasuryHandler(treasuryHandlerAddress);

        _balances[_msgSender()] = totalSupply();

        emit Transfer(address(0), _msgSender(), totalSupply());
    }

    function name() public pure returns (string memory) {
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
        require(
            currentAllowance >= amount,
            "FLOKI:transferFrom:ALLOWANCE_EXCEEDED: Transfer amount exceeds allowance."
        );
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
        require(
            currentAllowance >= subtractedValue,
            "FLOKI:decreaseAllowance:ALLOWANCE_UNDERFLOW: Subtraction results in sub-zero allowance."
        );
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), block.chainid, address(this))
        );
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);

        require(signatory != address(0), "FLOKI:delegateBySig:INVALID_SIGNATURE: Received signature was invalid.");
        require(block.timestamp <= expiry, "FLOKI:delegateBySig:EXPIRED_SIGNATURE: Received signature has expired.");
        require(nonce == nonces[signatory]++, "FLOKI:delegateBySig:INVALID_NONCE: Received nonce was invalid.");

        return _delegate(signatory, delegatee);
    }

    function getVotesAtBlock(address account, uint32 blockNumber) public view returns (uint224) {
        require(
            blockNumber < block.number,
            "FLOKI:getVotesAtBlock:FUTURE_BLOCK: Cannot get votes at a block in the future."
        );

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance.
        if (checkpoints[account][nCheckpoints - 1].blockNumber <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance.
        if (checkpoints[account][0].blockNumber > blockNumber) {
            return 0;
        }

        // Perform binary search.
        uint32 lowerBound = 0;
        uint32 upperBound = nCheckpoints - 1;
        while (upperBound > lowerBound) {
            uint32 center = upperBound - (upperBound - lowerBound) / 2;
            Checkpoint memory checkpoint = checkpoints[account][center];

            if (checkpoint.blockNumber == blockNumber) {
                return checkpoint.votes;
            } else if (checkpoint.blockNumber < blockNumber) {
                lowerBound = center;
            } else {
                upperBound = center - 1;
            }
        }

        // No exact block found. Use last known balance before that block number.
        return checkpoints[account][lowerBound].votes;
    }

    function _delegate(address delegator, address delegatee) private {
        address currentDelegate = delegates[delegator];
        uint256 delegatorBalance = _balances[delegator];
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, uint224(delegatorBalance));
    }

    function _moveDelegates(
        address srcRep,
        address dstRep,
        uint224 amount
    ) private {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint224 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint224 srcRepNew = srcRepOld - amount;

                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint224 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint224 dstRepNew = dstRepOld + amount;

                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint224 oldVotes,
        uint224 newVotes
    ) private {
        uint32 blockNumber = uint32(block.number);

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].blockNumber == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "FLOKI:_approve:OWNER_ZERO: Cannot approve for the zero address.");
        require(spender != address(0), "FLOKI:_approve:SPENDER_ZERO: Cannot approve to the zero address.");

        _allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "FLOKI:_transfer:FROM_ZERO: Cannot transfer from the zero address.");
        require(to != address(0), "FLOKI:_transfer:TO_ZERO: Cannot transfer to the zero address.");
        require(amount > 0, "FLOKI:_transfer:ZERO_AMOUNT: Transfer amount must be greater than zero.");
        require(amount >= _balances[from], "FLOKI:_transfer:INSUFFICIENT_BALANCE: Transfer amount exceeds balance.");

        treasuryHandler.beforeTransferHandler(from, to, amount);

        uint256 tax = taxHandler.getTax(from, to, amount);
        uint256 taxedAmount = amount - tax;

        _balances[from] -= amount;
        _balances[to] += taxedAmount;
        _moveDelegates(delegates[from], delegates[to], uint224(taxedAmount));

        if (tax > 0) {
            _balances[address(treasuryHandler)] += tax;

            _moveDelegates(delegates[from], delegates[address(treasuryHandler)], uint224(tax));

            emit Transfer(from, address(this), tax);
        }

        treasuryHandler.afterTransferHandler(from, to, amount);

        emit Transfer(from, to, taxedAmount);
    }
}
