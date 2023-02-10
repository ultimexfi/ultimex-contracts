// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract xUlti is ERC20("xUlti", "xULTI"){
    using SafeMath for uint256;
    IERC20 public ulti;

    struct TrackedUserInfo {
        address addr;
        uint256 depositTxs;
        uint256 withdrawTxs;
        uint256 lastActionBlock;
    }

    uint256 public depositTxs;
    uint256 public withdrawTxs;
    mapping(address => uint256) public trackedUserIndex;
    TrackedUserInfo[] public trackedUserInfo;

    constructor(IERC20 _ulti) public {
        ulti = _ulti;
    }

    function _updateTrackedUserInfo(address _user) internal {
        uint256 id = trackedUserIndex[_user];
        if (id > 0) {
            trackedUserInfo[id - 1].lastActionBlock = block.number;
            return;
        }
        trackedUserInfo.push(TrackedUserInfo({
            addr: _user,
            depositTxs: 0,
            withdrawTxs: 0,
            lastActionBlock: block.number
        }));
        trackedUserIndex[_user] = trackedUserInfo.length;
    }

    function _updateDepositTx(address _user) internal {
        _updateTrackedUserInfo(_user);
        TrackedUserInfo storage user = trackedUserInfo[trackedUserIndex[_user] - 1];
        user.depositTxs = user.depositTxs + 1;
        depositTxs = depositTxs + 1;
    }

    function _updateWithdrawTx(address _user) internal {
        _updateTrackedUserInfo(_user);
        TrackedUserInfo storage user = trackedUserInfo[trackedUserIndex[_user] - 1];
        user.withdrawTxs = user.withdrawTxs + 1;
        withdrawTxs = withdrawTxs + 1;
    }

    function totalUsers() external view returns (uint256) {
        return trackedUserInfo.length;
    }

    function enter(uint256 _amount) public {
        _updateDepositTx(msg.sender);
        uint256 totalUlti = ulti.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        if (totalShares == 0 || totalUlti == 0) {
            _mint(msg.sender, _amount);
        } 
        else {
            uint256 what = _amount.mul(totalShares).div(totalUlti);
            _mint(msg.sender, what);
        }
        ulti.transferFrom(msg.sender, address(this), _amount);
    }

    function leave(uint256 _share) public {
        _updateWithdrawTx(msg.sender);
        uint256 totalShares = totalSupply();
        uint256 what = _share.mul(ulti.balanceOf(address(this))).div(totalShares);
        _burn(msg.sender, _share);
        ulti.transfer(msg.sender, what);
    }

    function ultiBalance(address _account) external view returns (uint256 ultiAmount) {
        uint256 xultiAmount = balanceOf(_account);
        uint256 totalXUlti = totalSupply();
        ultiAmount = xultiAmount.mul(ulti.balanceOf(address(this))).div(totalXUlti);
    }

    function xultiForUlti(uint256 _xultiAmount) external view returns (uint256 ultiAmount) {
        uint256 totalXUlti = totalSupply();
        ultiAmount = _xultiAmount.mul(ulti.balanceOf(address(this))).div(totalXUlti);
    }

    function ultiForXUlti(uint256 _ultiAmount) external view returns (uint256 xultiAmount) {
        uint256 totalUlti = ulti.balanceOf(address(this));
        uint256 totalXUlti = totalSupply();
        if (totalXUlti == 0 || totalUlti == 0) {
            xultiAmount = _ultiAmount;
        }
        else {
            xultiAmount = _ultiAmount.mul(totalXUlti).div(totalUlti);
        }
    }

    // Copied and modified from YAM code:
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernanceStorage.sol
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernance.sol
    // Which is copied and modified from COMPOUND:
    // https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/Comp.sol

    // A record of each accounts delegate
    mapping (address => address) internal _delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    // A record of states for signing / validating signatures
    mapping (address => uint) public nonces;

      /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);
    
    function burn(address _from, uint256 _amount) private {
        _burn(_from, _amount);
        _moveDelegates(_delegates[_from], address(0), _amount);
    }

    function mint(address recipient, uint256 _amount) private {
        _mint(recipient, _amount);

        _initDelegates(recipient);

        _moveDelegates(address(0), _delegates[recipient], _amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) 
    public virtual override returns (bool)
    {
        bool result = super.transferFrom(sender, recipient, amount); // Call parent hook

        _initDelegates(recipient);

        _moveDelegates(_delegates[sender], _delegates[recipient], amount);

        return result;
    }

    function transfer(address recipient, uint256 amount) 
    public virtual override returns (bool)
    {
        bool result = super.transfer(recipient, amount); // Call parent hook

        _initDelegates(recipient);

        _moveDelegates(_delegates[_msgSender()], _delegates[recipient], amount);

        return result;
    }

    // initialize delegates mapping of recipient if not already
    function _initDelegates(address recipient) internal {
        if(_delegates[recipient] == address(0)) {
            _delegates[recipient] = recipient;
        }
    }

    /**
     * @param delegator The address to get delegates for
     */
    function delegates(address delegator)
        external
        view
        returns (address)
    {
        return _delegates[delegator];
    }

   /**
    * @notice Delegate votes from `msg.sender` to `delegatee`
    * @param delegatee The address to delegate votes to
    */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(address delegatee, uint nonce, uint expiry, uint8 v, bytes32 r, bytes32 s ) external {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name())),
                getChainId(),
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                DELEGATION_TYPEHASH,
                delegatee,
                nonce,
                expiry
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "xULTI::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "xULTI::delegateBySig: invalid nonce");
        require(block.timestamp <= expiry, "xULTI::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account)
        external
        view
        returns (uint256)
    {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber)
        external
        view
        returns (uint256)
    {
        require(blockNumber < block.number, "xULTI::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee)
        internal
    {
        address currentDelegate = _delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator); // balance of underlying ULTIs (not scaled);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint256 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                // decrease old representative
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = srcRepOld - amount;
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                // increase new representative
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = dstRepOld + amount;
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    )
        internal
    {
        uint32 blockNumber = safe32(block.number, "xULTI::_writeCheckpoint: block number exceeds 32 bits");

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal view returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }
}