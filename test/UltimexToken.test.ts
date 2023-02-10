import { ethers, network } from "hardhat"
import { expect } from "chai"

describe("Ulti", function () {
  before(async function () {
    this.Ulti = await ethers.getContractFactory("Ulti")
    this.signers = await ethers.getSigners()
    this.alice = this.signers[0]
    this.bob = this.signers[1]
    this.carol = this.signers[2]
  })

  beforeEach(async function () {
    this.ulti = await this.Ulti.deploy()
    await this.ulti.deployed()
  })

  it("should have correct name and symbol and decimal", async function () {
    const name = await this.ulti.name()
    const symbol = await this.ulti.symbol()
    const decimals = await this.ulti.decimals()
    expect(name, "Ulti")
    expect(symbol, "ULTI")
    expect(decimals, "18")
  })

  it("should only allow owner to mint token", async function () {
    await this.ulti.mint(this.alice.address, "100")
    await this.ulti.mint(this.bob.address, "1000")
    await expect(this.ulti.connect(this.bob).mint(this.carol.address, "1000", { from: this.bob.address })).to.be.revertedWith(
      "Ownable: caller is not the owner"
    )
    const totalSupply = await this.ulti.totalSupply()
    const aliceBal = await this.ulti.balanceOf(this.alice.address)
    const bobBal = await this.ulti.balanceOf(this.bob.address)
    const carolBal = await this.ulti.balanceOf(this.carol.address)
    expect(totalSupply).to.equal("430000000000000000000001100")
    expect(aliceBal).to.equal("430000000000000000000000100")
    expect(bobBal).to.equal("1000")
    expect(carolBal).to.equal("0")
  })

  it("should supply token transfers prultirly", async function () {
    await this.ulti.mint(this.alice.address, "100")
    await this.ulti.mint(this.bob.address, "1000")
    await this.ulti.transfer(this.carol.address, "10")
    await this.ulti.connect(this.bob).transfer(this.carol.address, "100", {
      from: this.bob.address,
    })
    const totalSupply = await this.ulti.totalSupply()
    const aliceBal = await this.ulti.balanceOf(this.alice.address)
    const bobBal = await this.ulti.balanceOf(this.bob.address)
    const carolBal = await this.ulti.balanceOf(this.carol.address)
    expect(totalSupply, "430000000000000000000001100")
    expect(aliceBal, "430000000000000000000000090")
    expect(bobBal, "900")
    expect(carolBal, "110")
  })

  it("should fail if you try to do bad transfers", async function () {
    await expect(this.ulti.transfer(this.carol.address, "430000000000000000000000001")).to.be.revertedWith("ERC20: transfer amount exceeds balance")
    await expect(this.ulti.connect(this.bob).transfer(this.carol.address, "1", { from: this.bob.address })).to.be.revertedWith(
      "ERC20: transfer amount exceeds balance"
    )
  })

  it("should not exceed max supply of 1b", async function () {
    await expect(this.ulti.mint(this.alice.address, "570000000000000000000000001")).to.be.revertedWith("ERC20Capped: Max supply exceeded")
    await this.ulti.mint(this.alice.address, "570000000000000000000000000")
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})