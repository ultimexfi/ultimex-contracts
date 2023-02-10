// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
import "../libraries/BoringMath.sol";
import "../libraries/BoringERC20.sol";

import "../interfaces/IUltimexERC20.sol";
import "../interfaces/IUltimexPair.sol";
import "../interfaces/IUltimexFactory.sol";

import "./BoringOwnable.sol";

contract UltimexMaker is BoringOwnable {
    using BoringMath for uint256;
    using BoringERC20 for IERC20;

    IUltimexFactory public immutable factory;
    // 
    address public immutable xulti;
    // 
    address private immutable ulti;
    // 
    address private immutable weth;
    // 
    uint256 public boughtUlti;

    mapping(address => address) internal _bridges;

    event LogBridgeSet(address indexed token, address indexed bridge);
    event LogConvertSingleToken(
        address indexed server,
        address indexed token,
        uint256 amount,
        uint256 amountULTI
    );
    event LogConvert(
        address indexed server,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 amountULTI
    );

    constructor(
        address _factory,
        address _xulti,
        address _ulti,
        address _weth
    ) public {
        factory = IUltimexFactory(_factory);
        xulti = _xulti;
        ulti = _ulti;
        weth = _weth;
    }

    receive() external payable {
        assert(msg.sender == weth); // only accept ETH via fallback from the WETH contract
    }

    function bridgeFor(address token) public view returns (address bridge) {
        bridge = _bridges[token];
        if (bridge == address(0)) {
            bridge = weth;
        }
    }

    function setBridge(address token, address bridge) external onlyOwner {
        require(
            token != ulti && token != weth && token != bridge,
            "UltimexMaker: Invalid bridge"
        );

        _bridges[token] = bridge;
        emit LogBridgeSet(token, bridge);
    }

    function convertSingleToken(address token) external {
        uint256 amount = IERC20(token).balanceOf(address(this));
        emit LogConvertSingleToken(
            msg.sender,
            token,
            amount,
            _toULTI(token, amount)
        );
    }

    function convertMultipleSingleToken(
        address[] calldata token
    ) external {
        uint256 len = token.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 amount = IERC20(token[i]).balanceOf(address(this));
            emit LogConvertSingleToken(
                msg.sender,
                token[i],
                amount,
                _toULTI(token[i], amount)
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
        emit LogConvert(
            msg.sender,
            token0,
            token1,
            amount0,
            amount1,
            _convertStep(token0, token1, amount0, amount1)
        );
    }

    function _convertStep(address token0, address token1, uint256 amount0, uint256 amount1) internal returns(uint256 ultiOut) {
        if (token0 == token1) {
            uint256 amount = amount0.add(amount1);
            if (token0 == ulti) {
                IERC20(ulti).safeTransfer(xulti, amount);
                ultiOut = amount;
            } else if (token0 == weth) {
                ultiOut = _toULTI(weth, amount);
            } else {
                address bridge = bridgeFor(token0);
                amount = _swap(token0, bridge, amount, address(this));
                ultiOut = _convertStep(bridge, bridge, amount, 0);
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
            address bridge0 = bridgeFor(token0);
            address bridge1 = bridgeFor(token1);
            if (bridge0 == token1) { // eg. YFI - USDT - and bridgeFor(X) = USDT
                ultiOut = _convertStep(bridge0, token1,
                    _swap(token0, bridge0, amount0, address(this)),
                    amount1
                );
            } else if (bridge1 == token0) { // eg. WBTC - CRV - and bridgeFor(CRV) = WBTC
                ultiOut = _convertStep(token0, bridge1,
                    amount0,
                    _swap(token1, bridge1, amount1, address(this))
                );
            } else {
                ultiOut = _convertStep(bridge0, bridge1, // eg. USDT - CRV - and bridgeFor(CRV) = WBTC
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
        boughtUlti = boughtUlti.add(amountOut);
    }
}