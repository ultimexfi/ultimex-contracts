import { BigNumber, Signer } from "ethers"
import { ethers } from "hardhat"
import { ERC20 } from "../../types"

export const BASE_TEN = 10
export const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000"

export function encodeParameters(types: any, values: any) {
  const abi = new ethers.utils.AbiCoder()
  return abi.encode(types, values)
}

export async function prepare(thisObject: any, contracts: any) {
  for (let i in contracts) {
    let contract = contracts[i]
    thisObject[contract] = await ethers.getContractFactory(contract)
  }
  thisObject.signers = await ethers.getSigners()
  thisObject.alice = thisObject.signers[0]
  thisObject.bob = thisObject.signers[1]
  thisObject.carol = thisObject.signers[2]
  thisObject.dev = thisObject.signers[3]
  thisObject.alicePrivateKey = ""
  thisObject.bobPrivateKey = ""
  thisObject.carolPrivateKey = ""
}

export async function deploy(thisObject: any, contracts: any) {
  for (let i in contracts) {
    let contract = contracts[i]
    thisObject[contract[0]] = await contract[1].deploy(...(contract[2] || []))
    await thisObject[contract[0]].deployed()
  }
}

export async function createMLP(thisObject: any, name: any, tokenA: any, tokenB: any, amount: any) {
  const createPairTx = await thisObject.factory.createPair(tokenA.address, tokenB.address)

  const _pair = (await createPairTx.wait()).events[0].args.pair

  thisObject[name] = await thisObject.UltimexPair.attach(_pair)

  await tokenA.transfer(thisObject[name].address, amount)
  await tokenB.transfer(thisObject[name].address, amount)

  await thisObject[name].mint(thisObject.alice.address)
}
// Defaults to e18 using amount * 10^18
export function getBigNumber(amount: any, decimals = 18) {
  return BigNumber.from(amount).mul(BigNumber.from(BASE_TEN).pow(decimals))
}

export async function asyncForEach<T>(array: Array<T>, callback: (item: T, index: number) => void): Promise<void> {
  for (let index = 0; index < array.length; index++) {
    await callback(array[index], index);
  }
}

export async function setupStableSwap(thisObject: any, owner: any) {
  const LpTokenFactory = await ethers.getContractFactory("LPToken", owner);
  thisObject.lpTokenBase = await LpTokenFactory.deploy();
  await thisObject.lpTokenBase.deployed();
  await thisObject.lpTokenBase.initialize("Test Token", "TEST");

  const AmpUtilsFactory = await ethers.getContractFactory("AmplificationUtils", owner);
  thisObject.amplificationUtils = await AmpUtilsFactory.deploy();
  await thisObject.amplificationUtils.deployed();

  const SwapUtilsFactory = await ethers.getContractFactory("SwapUtils", owner);
  thisObject.swapUtils = await SwapUtilsFactory.deploy();
  await thisObject.swapUtils.deployed();

  const SwapFlashLoanFactory = await ethers.getContractFactory("SwapFlashLoan", {
    libraries: {
      SwapUtils: thisObject.swapUtils.address,
      AmplificationUtils: thisObject.amplificationUtils.address,
    },
  });
  thisObject.swapFlashLoan = await SwapFlashLoanFactory.connect(owner).deploy();
  await thisObject.swapFlashLoan.deployed();
}

export async function getUserTokenBalance(address: string | Signer, token: ERC20): Promise<BigNumber> {
  if (address instanceof Signer) {
    address = await address.getAddress();
  }
  return token.balanceOf(address);
}

export async function getUserTokenBalances(address: string | Signer, tokens: ERC20[]): Promise<BigNumber[]> {
  const balanceArray = [];

  if (address instanceof Signer) {
    address = await address.getAddress();
  }

  for (const token of tokens) {
    balanceArray.push(await token.balanceOf(address));
  }

  return balanceArray;
}

export * from "./time"