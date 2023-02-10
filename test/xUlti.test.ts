import { ethers, network } from "hardhat"
import { expect } from "chai"

describe("xUlti", function () {
  before(async function () {
    this.Ulti = await ethers.getContractFactory("Ulti")
    this.xUlti = await ethers.getContractFactory("xUlti")

    this.signers = await ethers.getSigners()
    this.alice = this.signers[0]
    this.bob = this.signers[1]
    this.carol = this.signers[2]
  })

  beforeEach(async function () {
    this.ulti = await this.Ulti.deploy()
    this.xulti = await this.xUlti.deploy(this.ulti.address)
    this.ulti.mint(this.alice.address, "100")
    this.ulti.mint(this.bob.address, "100")
    this.ulti.mint(this.carol.address, "100")
  })

  it("should not allow enter if not enough approve", async function () {
    await expect(this.xulti.enter("100")).to.be.revertedWith("ERC20: transfer amount exceeds allowance")
    await this.ulti.approve(this.xulti.address, "50")
    await expect(this.xulti.enter("100")).to.be.revertedWith("ERC20: transfer amount exceeds allowance")
    await this.ulti.approve(this.xulti.address, "100")
    await this.xulti.enter("100")
    expect(await this.xulti.balanceOf(this.alice.address)).to.equal("100")
  })

  it("should not allow withraw more than what you have", async function () {
    await this.ulti.approve(this.xulti.address, "100")
    await this.xulti.enter("100")
    await expect(this.xulti.leave("200")).to.be.revertedWith("ERC20: burn amount exceeds balance")
  })

  it("should work with more than one participant", async function () {
    await this.ulti.approve(this.xulti.address, "100")
    await this.ulti.connect(this.bob).approve(this.xulti.address, "100", { from: this.bob.address })
    // Alice enters and gets 20 shares. Bob enters and gets 10 shares.
    await this.xulti.enter("20")
    await this.xulti.connect(this.bob).enter("10", { from: this.bob.address })
    expect(await this.xulti.balanceOf(this.alice.address)).to.equal("20")
    expect(await this.xulti.balanceOf(this.bob.address)).to.equal("10")
    expect(await this.ulti.balanceOf(this.xulti.address)).to.equal("30")
    // xUlti get 20 more ULTIs from an external source.
    await this.ulti.connect(this.carol).transfer(this.xulti.address, "20", { from: this.carol.address })
    // Alice deposits 10 more ULTIs. She should receive 10*30/50 = 6 shares.
    await this.xulti.enter("10")
    expect(await this.xulti.balanceOf(this.alice.address)).to.equal("26")
    expect(await this.xulti.balanceOf(this.bob.address)).to.equal("10")
    // Bob withdraws 5 shares. He should receive 5*60/36 = 8 shares
    await this.xulti.connect(this.bob).leave("5", { from: this.bob.address })
    expect(await this.xulti.balanceOf(this.alice.address)).to.equal("26")
    expect(await this.xulti.balanceOf(this.bob.address)).to.equal("5")
    expect(await this.ulti.balanceOf(this.xulti.address)).to.equal("52")
    expect(await this.ulti.balanceOf(this.alice.address)).to.equal("430000000000000000000000070")
    expect(await this.ulti.balanceOf(this.bob.address)).to.equal("98")
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})