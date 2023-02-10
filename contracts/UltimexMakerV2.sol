// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IUltimexERC20.sol";
import "../interfaces/IUltimexPair.sol";
import "../interfaces/IUltimexFactory.sol";

contract UltimexMakerV2 is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IUltimexFactory public immutable factory;
    address public immutable xulti;
    address private immutable ulti;
    address private immutable usdt;
    address private immutable weth;
    uint256 public boughtUsdt;
    uint256 public boughtUlti;

    address public treasury;
    uint256 public ultiBuybackPercent; // 1000 <=> 100%

    mapping(address => address) internal _ultiBridges;
    mapping(address => address) internal _usdtBridges;

    event LogUltiBridgeSet(address indexed token, address indexed bridge);
    event LogUsdtBridgeSet(address indexed token, address indexed bridge);
    event LogTreasurySet(address indexed treasury);
    event LogUltiBuybackPercentSet(uint256 percent);
    event LogConvertSingleToken(
        address indexed server,
        address indexed token,
        uint256 amount,
        uint256 amountULTI,
        uint256 amountUSDT
    );
    event LogConvertToULTI(
        address indexed server,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 amount
    );
    event LogConvertToUSDT(
        address indexed server,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 amount
    );

    constructor(
        address _factory,
        address _xulti,
        address _ulti,
        address _usdt,
        address _weth,
        address _treasury
    ) public {
        factory = IUltimexFactory(_factory);
        xulti = _xulti;
        ulti = _ulti;
        usdt = _usdt;
        weth = _weth;
        treasury = _treasury;
        ultiBuybackPercent = 800; // default: 80%
    }

    receive() external payable {
        assert(msg.sender == weth); // only accept ETH via fallback from the WETH contract
    }

    function ultiBridgeFor(address token) public view returns (address bridge) {
        bridge = _ultiBridges[token];
        if (bridge == address(0)) {
            bridge = weth;
        }
    }

    function usdtBridgeFor(address token) public view returns (address bridge) {
        bridge = _usdtBridges[token];
        if (bridge == address(0)) {
            bridge = weth;
        }
    }

    function setUltiBridge(address token, address bridge) external onlyOwner {
        require(
            token != ulti && token != weth && token != bridge,
            "UltimexMaker: Invalid bridge"
        );

        _ultiBridges[token] = bridge;
        emit LogUltiBridgeSet(token, bridge);
    }

    function setUsdtBridge(address token, address bridge) external onlyOwner {
        require(
            token != usdt && token != weth && token != bridge,
            "UltimexMaker: Invalid bridge"
        );

        _usdtBridges[token] = bridge;
        emit LogUsdtBridgeSet(token, bridge);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit LogTreasurySet(_treasury);
    }

    function setUltiBuybackPercent(uint256 _ultiBuybackPercent) external onlyOwner {
        require(
            _ultiBuybackPercent <= 1000,
            "UltimexMaker: Invalid percent"
        );

        ultiBuybackPercent = _ultiBuybackPercent;
        emit LogUltiBuybackPercentSet(_ultiBuybackPercent);
    }

    function calculate(uint256 _amount) internal view returns (uint256 amountToUlti, uint256 amountToUsdt) {
        amountToUlti = _amount.mul(ultiBuybackPercent).div(1000);
        amountToUsdt = _amount.sub(amountToUlti);
    }

    function convertSingleToken(address token) external {
        uint256 amount = IERC20(token).balanceOf(address(this));
        (uint256 amountToUlti, uint256 amountToUsdt) = calculate(amount);
        emit LogConvertSingleToken(
            msg.sender,
            token,
            amount,
            _toULTI(token, amountToUlti),
            _toUSDT(token, amountToUsdt)
        );
    }

    function convertMultipleSingleToken(
        address[] calldata token
    ) external {
        uint256 len = token.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 amount = IERC20(token[i]).balanceOf(address(this));
            (uint256 amountToUlti, uint256 amountToUsdt) = calculate(amount);
            emit LogConvertSingleToken(
                msg.sender,
                token[i],
                amount,
                _toULTI(token[i], amountToUlti),
                _toUSDT(token[i], amountToUsdt)
            );
        }
    }

    function convert(address token0, address token1) external {
        _convert(token0, token1);
    }

    function convertMultiple(
        address[] calldata token0,
        address[] calldata token1
    ) external {
        uint256 len = token0.length;
        for (uint256 i = 0; i < len; i++) {
            _convert(token0[i], token1[i]);
        }
    }

    function _convert(address token0, address token1) internal {
        IUltimexPair pair = IUltimexPair(factory.getPair(token0, token1));
        require(address(pair) != address(0), "UltimexMaker: Invalid pair");
        IERC20(address(pair)).safeTransfer(
            address(pair),
            pair.balanceOf(address(this))
        );
        (uint256 amount0, uint256 amount1) = pair.burn(address(this));
        if (token0 != pair.token0()) {
            (amount0, amount1) = (amount1, amount0);
        }
        (uint256 amountToUlti0, uint256 amountToUsdt0) = calculate(amount0);
        (uint256 amountToUlti1, uint256 amountToUsdt1) = calculate(amount1);

        uint256 ultiOut = _convertToULTIStep(token0, token1, amountToUlti0, amountToUlti1);
        boughtUlti = boughtUlti.add(ultiOut);
        emit LogConvertToULTI(
            msg.sender,
            token0,
            token1,
            amountToUlti0,
            amountToUlti1,
            ultiOut
        );

        uint256 usdtOut = _convertToUSDTStep(token0, token1, amountToUsdt0, amountToUsdt1);
        boughtUsdt = boughtUsdt.add(usdtOut);
        emit LogConvertToUSDT(
            msg.sender,
            token0,
            token1,
            amountToUsdt0,
            amountToUsdt1,
            usdtOut
        );
    }

    function _convertToULTIStep(address token0, address token1, uint256 amount0, uint256 amount1) internal returns(uint256 ultiOut) {
        if (token0 == token1) {
            uint256 amount = amount0.add(amount1);
            if (token0 == ulti) {
                IERC20(ulti).safeTransfer(xulti, amount);
                ultiOut = amount;
            } else if (token0 == weth) {
                ultiOut = _toULTI(weth, amount);
            } else {
                address bridge = ultiBridgeFor(token0);
                amount = _swap(token0, bridge, amount, address(this));
                ultiOut = _convertToULTIStep(bridge, bridge, amount, 0);
            }
        } else if (token0 == ulti) { // eg. ULTI - CORE
            IERC20(ulti).safeTransfer(xulti, amount0);
            ultiOut = _toULTI(token1, amount1).add(amount0);
        } else if (token1 == ulti) { // eg. USDT- ULTI
            IERC20(ulti).safeTransfer(xulti, amount1);
            ultiOut = _toULTI(token0, amount0).add(amount1);
        } else if (token0 == weth) { // eg. CORE - USDT
            ultiOut = _toULTI(weth, _swap(token1, weth, amount1, address(this)).add(amount0));
        } else if (token1 == weth) { // eg. USDT - CORE
            ultiOut = _toULTI(weth, _swap(token0, weth, amount0, address(this)).add(amount1));
        } else { // eg. YFI - USDT
            address bridge0 = ultiBridgeFor(token0);
            address bridge1 = ultiBridgeFor(token1);
            if (bridge0 == token1) {
                ultiOut = _convertToULTIStep(bridge0, token1,
                    _swap(token0, bridge0, amount0, address(this)),
                    amount1
                );
            } else if (bridge1 == token0) {
                ultiOut = _convertToULTIStep(token0, bridge1,
                    amount0,
                    _swap(token1, bridge1, amount1, address(this))
                );
            } else {
                ultiOut = _convertToULTIStep(bridge0, bridge1,
                    _swap(token0, bridge0, amount0, address(this)),
                    _swap(token1, bridge1, amount1, address(this))
                );
            }
        }
    }

    function _convertToUSDTStep(address token0, address token1, uint256 amount0, uint256 amount1) internal returns(uint256 usdtOut) {
        if (token0 == token1) {
            uint256 amount = amount0.add(amount1);
            if (token0 == usdt) {
                IERC20(usdt).safeTransfer(treasury, amount);
                usdtOut = amount;
            } else if (token0 == weth) {
                usdtOut = _toUSDT(weth, amount);
            } else {
                address bridge = usdtBridgeFor(token0);
                amount = _swap(token0, bridge, amount, address(this));
                usdtOut = _convertToUSDTStep(bridge, bridge, amount, 0);
            }
        } else if (token0 == usdt) { // eg. USDT - CORE
            IERC20(usdt).safeTransfer(treasury, amount0);
            usdtOut = _toUSDT(token1, amount1).add(amount0);
        } else if (token1 == usdt) { // eg. BNB - USDT
            IERC20(usdt).safeTransfer(treasury, amount1);
            usdtOut = _toUSDT(token0, amount0).add(amount1);
        } else if (token0 == weth) { // eg. CORE - BNB
            usdtOut = _toUSDT(weth, _swap(token1, weth, amount1, address(this)).add(amount0));
        } else if (token1 == weth) { // eg. BNB - CORE
            usdtOut = _toUSDT(weth, _swap(token0, weth, amount0, address(this)).add(amount1));
        } else { // eg. YFI - BNB
            address bridge0 = usdtBridgeFor(token0);
            address bridge1 = usdtBridgeFor(token1);
            if (bridge0 == token1) {
                usdtOut = _convertToUSDTStep(bridge0, token1,
                    _swap(token0, bridge0, amount0, address(this)),
                    amount1
                );
            } else if (bridge1 == token0) {
                usdtOut = _convertToUSDTStep(token0, bridge1,
                    amount0,
                    _swap(token1, bridge1, amount1, address(this))
                );
            } else {
                usdtOut = _convertToUSDTStep(bridge0, bridge1,
                    _swap(token0, bridge0, amount0, address(this)),
                    _swap(token1, bridge1, amount1, address(this))
                );
            }
        }
    }

    function _swap(address fromToken, address toToken, uint256 amountIn, address to) internal returns (uint256 amountOut) {
        IUltimexPair pair = IUltimexPair(factory.getPair(fromToken, toToken));
        require(address(pair) != address(0), "UltimexMaker: Cannot convert");

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        uint256 amountInWithFee = amountIn.mul(997);
        if (fromToken == pair.token0()) {
            amountOut = amountIn.mul(997).mul(reserve1) / reserve0.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(0, amountOut, to, new bytes(0));
        } else {
            amountOut = amountIn.mul(997).mul(reserve0) / reserve1.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(amountOut, 0, to, new bytes(0));
        }
    }

    function _toULTI(address token, uint256 amountIn) internal returns(uint256 amountOut) {
        amountOut = _swap(token, ulti, amountIn, xulti);
    }

    function _toUSDT(address token, uint256 amountIn) internal returns(uint256 amountOut) {
        amountOut = _swap(token, usdt, amountIn, treasury);
    }
}