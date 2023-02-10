import { ethers, network } from "hardhat"
import { expect } from "chai"
import { advanceTimeAndBlock, latest, duration, increase } from "./utilities"

describe("Vesting", function () {
  before(async function () {
    this.Ulti = await ethers.getContractFactory("Ulti")
    this.Vesting = await ethers.getContractFactory("Vesting")

    this.signers = await ethers.getSigners()
    this.alice = this.signers[0]
    this.bob = this.signers[1]
    this.carol = this.signers[2]

    this.vestingAmount = 1200;
  })

  beforeEach(async function () {
    this.ulti = await this.Ulti.deploy()
  })

  it("should set correct state variables", async function () {
    const startTime = await latest()
    this.vesting = await this.Vesting.deploy(
      this.ulti.address,
      this.bob.address,
      this.vestingAmount,
      startTime.add(10),
      startTime.add(20),
      startTime.add(110)
    )
    await this.vesting.deployed()

    const ulti = await this.vesting.ulti()
    const recipient = await this.vesting.recipient()
    const vestingAmount = await this.vesting.vestingAmount()
    const begin = await this.vesting.begin()
    const cliff = await this.vesting.cliff()
    const end = await this.vesting.end()

    expect(ulti).to.equal(this.ulti.address)
    expect(recipient).to.equal(this.bob.address)
    expect(vestingAmount).to.equal(this.vestingAmount)
    expect(begin).to.equal(startTime.add(10))
    expect(cliff).to.equal(startTime.add(20))
    expect(end).to.equal(startTime.add(110))
  })

  it("should check recipient is set correctly", async function () {
    const startTime = await latest()
    this.vesting = await this.Vesting.deploy(
      this.ulti.address,
      this.bob.address,
      this.vestingAmount,
      startTime.add(10),
      startTime.add(20),
      startTime.add(110)
    )
    await this.vesting.deployed()

    await this.vesting.setRecipient(this.carol.address)
    expect(await this.vesting.recipient()).to.equal(this.carol.address)
  })

  it("should not allow to claim before cliff", async function () {
    const startTime = await latest() // t+0
    this.vesting = await this.Vesting.deploy(
      this.ulti.address,
      this.bob.address,
      this.vestingAmount,
      startTime.add(10),
      startTime.add(20),
      startTime.add(110)
    )
    await this.vesting.deployed() // t+1
    await this.ulti.transfer(this.vesting.address, "1200") // t+2
    await advanceTimeAndBlock(16) // t+18

    await expect(this.vesting.claim()).to.be.revertedWith("Vesting: NOT NOW") // t+19
  })

  it("should claim the correct amount", async function () {
    const startTime = await latest() // t+0
    this.vesting = await this.Vesting.deploy(
      this.ulti.address,
      this.bob.address,
      this.vestingAmount,
      startTime.add(10),
      startTime.add(20),
      startTime.add(110)
    )
    await this.vesting.deployed() // t+1
    await this.ulti.transfer(this.vesting.address, "1200") // t+2
    await advanceTimeAndBlock(17) // t+29


    expect(await this.ulti.balanceOf(this.bob.address)).to.equal(0)
    await this.vesting.claim() // t+20
    expect(await this.ulti.balanceOf(this.bob.address)).to.be.within(120, 132)
    await this.vesting.claim() // t+21
    expect(await this.ulti.balanceOf(this.bob.address)).to.be.within(132, 144)
  })

  it("should be able to claim all", async function () {
    const startTime = await latest() // t+0
    this.vesting = await this.Vesting.deploy(
      this.ulti.address,
      this.bob.address,
      this.vestingAmount,
      startTime.add(10),
      startTime.add(20),
      startTime.add(110)
    )
    await this.vesting.deployed() // t+1
    await this.ulti.transfer(this.vesting.address, "1200") // t+2
    await advanceTimeAndBlock(110) // t+112


    expect(await this.ulti.balanceOf(this.bob.address)).to.equal(0)
    await this.vesting.claim() // t+113
    expect(await this.ulti.balanceOf(this.bob.address)).to.equal(1200)
    await this.vesting.claim() // t+114
    expect(await this.ulti.balanceOf(this.bob.address)).to.equal(1200)
  })

  it("no need to transfer whole vesting amount at once", async function () {
    const startTime = await latest() // t+0
    this.vesting = await this.Vesting.deploy(
      this.ulti.address,
      this.bob.address,
      this.vestingAmount,
      startTime.add(10),
      startTime.add(20),
      startTime.add(110)
    )
    await this.vesting.deployed() // t+1
    await this.ulti.transfer(this.vesting.address, "1000") // t+2
    await advanceTimeAndBlock(110) // t+112


    expect(await this.ulti.balanceOf(this.bob.address)).to.equal(0)
    await this.vesting.claim() // t+113
    expect(await this.ulti.balanceOf(this.bob.address)).to.equal(1000)
    expect(await this.vesting.lastUpdate()).to.be.within(startTime.add(93), startTime.add(94))
    await this.ulti.transfer(this.vesting.address, "200") // t+114
    await this.vesting.claim() // t+115
    expect(await this.ulti.balanceOf(this.bob.address)).to.equal(1200)
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})