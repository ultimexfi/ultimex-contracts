import { ethers, network } from "hardhat"
import { expect } from "chai"
import { advanceTimeAndBlock, latest, duration, increase } from "./utilities"

describe("MasterChef", function () {
    before(async function () {
        this.signers = await ethers.getSigners()
        this.alice = this.signers[0]
        this.bob = this.signers[1]
        this.carol = this.signers[2]
        this.minter = this.signers[3]

        this.MasterChef = await ethers.getContractFactory("MasterChef")
        this.Rewarder = await ethers.getContractFactory("Rewarder")
        this.Ulti = await ethers.getContractFactory("Ulti")
        this.ERC20Mock = await ethers.getContractFactory("ERC20Mock", this.minter)

        this.burnPercent = '10000000000000000000'
        this.lpPercent = '90000000000000000000'
        this.ultiPerSecond = 100
        this.secOffset = 1
        this.tokenOffset = 1
    })

    beforeEach(async function () {
        this.ulti = await this.Ulti.deploy()
        await this.ulti.deployed()
    })

    it("should set correct state variables", async function () {
        // We make start time 60 seconds past the last block
        const startTime = (await latest()).add(60)
        this.chef = await this.MasterChef.deploy(
            this.ulti.address,
            this.ultiPerSecond,
            this.burnPercent,
            startTime
        )
        await this.chef.deployed()

        await this.ulti.transferOwnership(this.chef.address)

        const ulti = await this.chef.ulti()
        const owner = await this.ulti.owner()
        const burnPercent = await this.chef.burnPercent()

        expect(ulti).to.equal(this.ulti.address)
        expect(owner).to.equal(this.chef.address)
        expect(burnPercent).to.equal(this.burnPercent)
    })

    it("should check burn percent is set correctly", async function () {
        const startTime = (await latest()).add(60)
        this.chef = await this.MasterChef.deploy(
            this.ulti.address,
            this.ultiPerSecond,
            this.burnPercent,
            startTime
        )
        await this.chef.deployed()

        await this.chef.setPercent(this.burnPercent) // t-57
        expect(await this.chef.burnPercent()).to.equal("10000000000000000000")
        await expect(this.chef.setPercent("120000000000000000000")).to.be.revertedWith("setPercent: Percent cannot exceed 100")
        await expect(this.chef.setPercent("100000000000000000000")).to.be.revertedWith("setPercent: Percent cannot exceed 100")
    })

    context("With ERC/LP token added to the field", function () {
        beforeEach(async function () {
            this.lp = await this.ERC20Mock.deploy("LPToken", "LP", 18, "10000000000")

            await this.lp.transfer(this.alice.address, "1000")

            await this.lp.transfer(this.bob.address, "1000")

            await this.lp.transfer(this.carol.address, "1000")

            this.lp2 = await this.ERC20Mock.deploy("LPToken2", "LP2", 18, "10000000000")

            await this.lp2.transfer(this.alice.address, "1000")

            await this.lp2.transfer(this.bob.address, "1000")

            await this.lp2.transfer(this.carol.address, "1000")

            this.bonusReward = await this.ERC20Mock.deploy("BonusToken", "BONUS", 18, "10000000000")
        })



        it("should give prultir ULTIs after updating emission rate", async function () {
            const startTime = (await latest()).add(60)
            this.chef = await this.MasterChef.deploy(
                this.ulti.address,
                this.ultiPerSecond,
                this.burnPercent,
                startTime
            )
            await this.chef.deployed() // t-59
            this.rewarder = await this.Rewarder.deploy(
                this.bonusReward.address,
                this.lp.address,
                10,
                this.chef.address,
                startTime
            )
            await this.rewarder.deployed() // t-58
            await this.bonusReward.transfer(this.rewarder.address, "1000000") // t-57

            await this.ulti.transferOwnership(this.chef.address) // t-56
            await this.chef.setPercent(this.burnPercent) // t-55

            await this.lp.connect(this.alice).approve(this.chef.address, "1000", { from: this.alice.address }) // t-54
            await this.chef.addPool("10", this.lp.address, this.rewarder.address) // t-53
            // Alice deposits 10 LPs at t+10
            await advanceTimeAndBlock(98) // t+9
            await this.chef.connect(this.alice).deposit(0, "10", { from: this.alice.address }) // t+10
            // At t+110,
            // Alice should have:   100*100*0.9 = 9000 (+90) ULTI
            //                      100*10 = 1000 (+10) BONUS
            await advanceTimeAndBlock(100) // t+110
            expect((await this.chef.pendingReward(0, this.alice.address)).pendingUlti).to.be.within(9000, 9090)
            expect((await this.chef.pendingReward(0, this.alice.address)).pendingBonus).to.be.within(1000, 1010)
            // Lower emission rate to 40 ULTI per sec
            await this.chef.setEmissionRate("40") // t+111
            // At t+115,
            // Alice should have:   9000 + 1*100*0.9 + 4*40*0.9 = 9234 (+36) ULTI
            //                      1000 + 1*10 + 4*10 = 1050 (+10) BONUS
            await advanceTimeAndBlock(4) // t+115
            expect((await this.chef.pendingReward(0, this.alice.address)).pendingUlti).to.be.within(9234, 9270)
            expect((await this.chef.pendingReward(0, this.alice.address)).pendingBonus).to.be.within(1050, 1060)
        })

        it("should not allow same LP token to be added twice", async function () {
            const startTime = (await latest()).add(60)
            this.chef = await this.MasterChef.deploy(
                this.ulti.address,
                this.ultiPerSecond,
                this.burnPercent,
                startTime
            )
            await this.chef.deployed()
            expect(await this.chef.poolLength()).to.equal("0")

            await this.chef.addPool("100", this.lp.address, "0x0000000000000000000000000000000000000000")
            expect(await this.chef.poolLength()).to.equal("1")
        })

        it("should allow a given pool's allocation weight to be updated", async function () {
            const startTime = (await latest()).add(60)
            this.chef = await this.MasterChef.deploy(
                this.ulti.address,
                this.ultiPerSecond,
                this.burnPercent,
                startTime
            )
            await this.chef.deployed()
            await this.chef.addPool("100", this.lp.address, "0x0000000000000000000000000000000000000000")
            expect((await this.chef.poolInfo(0)).allocPoint).to.equal("100")
            await this.chef.setPool("0", "150", "0x0000000000000000000000000000000000000000")
            expect((await this.chef.poolInfo(0)).allocPoint).to.equal("150")
        })

        it("should allow emergency withdraw", async function () {
            const startTime = (await latest()).add(60)
            this.chef = await this.MasterChef.deploy(
                this.ulti.address,
                this.ultiPerSecond,
                this.burnPercent,
                startTime
            )
            await this.chef.deployed()

            await this.chef.addPool("100", this.lp.address, "0x0000000000000000000000000000000000000000")

            await this.lp.connect(this.bob).approve(this.chef.address, "1000")

            await this.chef.connect(this.bob).deposit(0, "100")

            expect(await this.lp.balanceOf(this.bob.address)).to.equal("900")

            await this.chef.connect(this.bob).emergencyWithdraw(0)

            expect(await this.lp.balanceOf(this.bob.address)).to.equal("1000")
        })

        it("should give out ULTIs only after farming time", async function () {
            const startTime = (await latest()).add(60)
            this.chef = await this.MasterChef.deploy(
                this.ulti.address,
                this.ultiPerSecond,
                this.burnPercent,
                startTime
            )
            await this.chef.deployed() // t-59

            await this.ulti.burn("430000000000000000000000000") // t-58 // burn to test easier with small number
            await this.ulti.transferOwnership(this.chef.address) // t-57
            await this.chef.setPercent(this.burnPercent) // t-56

            await this.chef.addPool("100", this.lp.address, "0x0000000000000000000000000000000000000000") // t-55

            await this.lp.connect(this.bob).approve(this.chef.address, "1000") // t-54
            await this.chef.connect(this.bob).deposit(0, "100") // t-53
            await advanceTimeAndBlock(40) // t-13

            await this.chef.connect(this.bob).deposit(0, "0") // t-12
            expect(await this.ulti.balanceOf(this.bob.address)).to.equal("0")
            await advanceTimeAndBlock(10) // t-2

            await this.chef.connect(this.bob).deposit(0, "0") // t-1
            expect(await this.ulti.balanceOf(this.bob.address)).to.equal("0")
            await advanceTimeAndBlock(10) // t+9

            await this.chef.connect(this.bob).deposit(0, "0") // t+10
            // Bob should have: 10*100*0.9 = 900 (+90)
            expect(await this.ulti.balanceOf(this.bob.address)).to.be.within(900, 990)

            await advanceTimeAndBlock(4) // t+14
            await this.chef.connect(this.bob).deposit(0, "0") // t+15

            // At this point:
            //   Bob should have: 900 + 5*100*0.9 = 1350 (+90)
            expect(await this.ulti.balanceOf(this.bob.address)).to.be.within(1350, 1440)
            expect(await this.ulti.totalSupply()).to.be.within(1500, 1600)
        })

        it("should not distribute ULTIs if no one deposit", async function () {
            const startTime = (await latest()).add(60)
            this.chef = await this.MasterChef.deploy(
                this.ulti.address,
                this.ultiPerSecond,
                this.burnPercent,
                startTime
            )
            await this.chef.deployed() // t-59

            await this.ulti.burn("430000000000000000000000000") // t-58 // burn to test easier with small number
            await this.ulti.transferOwnership(this.chef.address) // t-57
            await this.chef.setPercent(this.burnPercent) // t-56

            await this.chef.addPool("100", this.lp.address, "0x0000000000000000000000000000000000000000") // t-55
            await this.lp.connect(this.bob).approve(this.chef.address, "1000") // t-54
            await advanceTimeAndBlock(100) // t+56

            expect(await this.ulti.totalSupply()).to.equal("0")
            await advanceTimeAndBlock(4) // t+60
            expect(await this.ulti.totalSupply()).to.equal("0")
            await advanceTimeAndBlock(5) // t+65
            await this.chef.connect(this.bob).deposit(0, "10") // t+66
            expect(await this.ulti.totalSupply()).to.equal("0")
            expect(await this.ulti.balanceOf(this.bob.address)).to.equal("0")
            expect(await this.lp.balanceOf(this.bob.address)).to.equal("990")
            await advanceTimeAndBlock(10) // t+76
            // Revert if Bob withdraws more than he deposited
            await expect(this.chef.connect(this.bob).withdraw(0, "11")).to.be.revertedWith("withdraw: Exceeded user's amount") // t+77
            await this.chef.connect(this.bob).withdraw(0, "10") // t+78

            // At this point:
            //   - Total supply should be: 12*100 = 1200 (+100)
            //   - Bob should have: 12*100*0.9 = 1080 (+90)
            expect(await this.ulti.totalSupply()).to.be.within(1200, 1300)
            expect(await this.ulti.balanceOf(this.bob.address)).to.be.within(1080, 1170)
        })

        it("should distribute ULTIs prultirly for each staker", async function () {
            const startTime = (await latest()).add(60)
            this.chef = await this.MasterChef.deploy(
                this.ulti.address,
                this.ultiPerSecond,
                this.burnPercent,
                startTime
            )
            await this.chef.deployed() // t-59
            this.rewarder = await this.Rewarder.deploy(
                this.bonusReward.address,
                this.lp.address,
                10,
                this.chef.address,
                startTime
            )
            await this.rewarder.deployed() // t-58
            await this.bonusReward.transfer(this.rewarder.address, "1000000") // t-57

            await this.ulti.burn("430000000000000000000000000") // t-56 // burn to test easier with small number
            await this.ulti.transferOwnership(this.chef.address) // t-55
            await this.chef.setPercent(this.burnPercent) // t-54

            await this.chef.addPool("100", this.lp.address, this.rewarder.address) // t-53
            await this.lp.connect(this.alice).approve(this.chef.address, "1000", {
                from: this.alice.address,
            }) // t-52
            await this.lp.connect(this.bob).approve(this.chef.address, "1000", {
                from: this.bob.address,
            }) // t-51
            await this.lp.connect(this.carol).approve(this.chef.address, "1000", {
                from: this.carol.address,
            }) // t-50

            // Alice deposits 10 LPs at t+10
            await advanceTimeAndBlock(59) // t+9
            await this.chef.connect(this.alice).deposit(0, "10", { from: this.alice.address }) // t+10
            // Bob deposits 20 LPs at t+14
            await advanceTimeAndBlock(3) // t+13
            await this.chef.connect(this.bob).deposit(0, "20") // t+14
            // Carol deposits 30 LPs at block t+18
            await advanceTimeAndBlock(3) // t+17
            await this.chef.connect(this.carol).deposit(0, "30", { from: this.carol.address }) // t+18
            // Alice deposits 10 more LPs at t+25. At this point:
            //   Alice should have: 4*100*0.9 + 4*1/3*100*0.9 + 2*1/6*100*0.9 = 510 (+90) ULTI
            //                      4*10 + 4*1/3*10 + 2*1/6*10 = 56.66 (+10) BONUS
            //   MasterChef should have: 1000 - 510 - 100 = 390 (+100) ULTI
            await advanceTimeAndBlock(1) // t+19
            await this.chef.connect(this.alice).deposit(0, "10", { from: this.alice.address }) // t+20
            expect(await this.ulti.totalSupply()).to.be.within(1000, 1100)
            // Becaues LP rewards are divided among participants and rounded down, we account
            // for rounding errors with an offset
            expect(await this.ulti.balanceOf(this.alice.address)).to.be.within(510 - this.tokenOffset, 600 + this.tokenOffset)
            expect(await this.bonusReward.balanceOf(this.alice.address)).to.be.within(56 - this.tokenOffset, 66 + this.tokenOffset)
            expect(await this.ulti.balanceOf(this.bob.address)).to.equal("0")
            expect(await this.bonusReward.balanceOf(this.bob.address)).to.equal("0")
            expect(await this.ulti.balanceOf(this.carol.address)).to.equal("0")
            expect(await this.bonusReward.balanceOf(this.carol.address)).to.equal("0")
            expect(await this.ulti.balanceOf(this.chef.address)).to.be.within(390 - this.tokenOffset, 490 + this.tokenOffset)
            expect(await this.bonusReward.balanceOf(this.chef.address)).to.equal("0")
            // Bob withdraws 5 LPs at block 30. At this point:
            //   Bob should have:   4*2/3*100*0.9 + 2*2/6*100*0.9 + 10*2/7*100*0.9 = 557 (+90) ULTI
            //                      4*2/3*10 + 2*2/6*10 + 10*2/7*10 = 61.9 (+10) BONUS
            //   MasterChef should have: 390 + 1000 - 557 - 100 = 733 (+100) ULTI
            await advanceTimeAndBlock(9) // t+29
            await this.chef.connect(this.bob).withdraw(0, "5", { from: this.bob.address }) // t+30
            expect(await this.ulti.totalSupply()).to.be.within(2000, 2100)
            expect(await this.ulti.balanceOf(this.alice.address)).to.be.within(510 - this.tokenOffset, 600 + this.tokenOffset)
            expect(await this.bonusReward.balanceOf(this.alice.address)).to.be.within(56 - this.tokenOffset, 66 + this.tokenOffset)
            expect(await this.ulti.balanceOf(this.bob.address)).to.be.within(557 - this.tokenOffset, 647 + this.tokenOffset)
            expect(await this.bonusReward.balanceOf(this.bob.address)).to.be.within(61 - this.tokenOffset, 71 + this.tokenOffset)
            expect(await this.ulti.balanceOf(this.carol.address)).to.equal("0")
            expect(await this.bonusReward.balanceOf(this.carol.address)).to.equal("0")
            expect(await this.ulti.balanceOf(this.chef.address)).to.be.within(733 - this.tokenOffset, 833 + this.tokenOffset)
            expect(await this.bonusReward.balanceOf(this.chef.address)).to.equal("0")
            // Alice withdraws 20 LPs at t+40
            // Bob withdraws 15 LPs at t+50
            // Carol withdraws 30 LPs at t+60
            await advanceTimeAndBlock(9) // t+39
            await this.chef.connect(this.alice).withdraw(0, "20", { from: this.alice.address }) // t+40
            await advanceTimeAndBlock(9) // t+49
            await this.chef.connect(this.bob).withdraw(0, "15", { from: this.bob.address }) // t+50
            await advanceTimeAndBlock(9) // t+59
            await this.chef.connect(this.carol).withdraw(0, "30", { from: this.carol.address }) // t+60
            expect(await this.ulti.totalSupply()).to.be.within(5000, 5100)
            // Alice should have:   510 + 10*2/7*100*0.9 + 10*2/6.5*100*0.9 = 1044 (+90) ULTI
            //                      56.66 + 10*2/7*10 + 10*2/6.5*10 = 116 (+10) BONUS
            expect(await this.ulti.balanceOf(this.alice.address)).to.be.within(1044 - this.tokenOffset, 1134 + this.tokenOffset)
            expect(await this.bonusReward.balanceOf(this.alice.address)).to.be.within(116 - this.tokenOffset, 126 + this.tokenOffset)
            // Bob should have: 557 + 10*1.5/6.5*100*0.9 + 10*1.5/4.5*100*0.9 = 1064 (+90) ULTI
            //                  61.9 + 10*1.5/6.5*10 + 10*1.5/4.5*10 = 118.31 (+10) BONUS
            expect(await this.ulti.balanceOf(this.bob.address)).to.be.within(1064 - this.tokenOffset, 1154 + this.tokenOffset)
            expect(await this.bonusReward.balanceOf(this.bob.address)).to.be.within(118 - this.tokenOffset, 128 + this.tokenOffset)
            // Carol should have:   2*3/6*100*0.9 + 10*3/7*100*0.9 + 10*3/6.5*100*0.9 + 10*3/4.5*100*0.9 + 10*100*0.9 = 2391 (+90) ULTI
            //                      2*3/6*10 + 10*3/7*10 + 10*3/6.5*10 + 10*3/4.5*10 + 10*10 = 265.67 (+10) BONUS
            expect(await this.ulti.balanceOf(this.carol.address)).to.be.within(2391 - this.tokenOffset, 2481 + this.tokenOffset)
            expect(await this.bonusReward.balanceOf(this.carol.address)).to.be.within(265 - this.tokenOffset, 275 + this.tokenOffset)
            // Masterchef should have nothing
            expect(await this.ulti.balanceOf(this.chef.address)).to.be.within(0, 0 + this.tokenOffset)
            expect(await this.bonusReward.balanceOf(this.chef.address)).to.be.within(0, 0 + this.tokenOffset)

            // // All of them should have 1000 LPs back.
            expect(await this.lp.balanceOf(this.alice.address)).to.equal("1000")
            expect(await this.lp.balanceOf(this.bob.address)).to.equal("1000")
            expect(await this.lp.balanceOf(this.carol.address)).to.equal("1000")
        })

        it("should give prultir ULTIs allocation to each pool", async function () {
            const startTime = (await latest()).add(60)
            this.chef = await this.MasterChef.deploy(
                this.ulti.address,
                this.ultiPerSecond,
                this.burnPercent,
                startTime
            )
            await this.chef.deployed() // t-59
            this.rewarder = await this.Rewarder.deploy(
                this.bonusReward.address,
                this.lp.address,
                10,
                this.chef.address,
                startTime
            )
            await this.rewarder.deployed() // t-58
            await this.bonusReward.transfer(this.rewarder.address, "1000000") // t-57

            await this.ulti.burn("430000000000000000000000000") // t-56 // burn to test easier with small number
            await this.ulti.transferOwnership(this.chef.address) // t-55
            await this.chef.setPercent(this.burnPercent) // t-54

            await this.lp.connect(this.alice).approve(this.chef.address, "1000", { from: this.alice.address }) // t-53
            await this.lp2.connect(this.bob).approve(this.chef.address, "1000", { from: this.bob.address }) // t-52
            // Add first LP to the pool with allocation 10
            await this.chef.addPool("10", this.lp.address, this.rewarder.address) // t-51
            // Alice deposits 10 LPs at t+10
            await advanceTimeAndBlock(60) // t+9
            await this.chef.connect(this.alice).deposit(0, "10", { from: this.alice.address }) // t+10
            // Add LP2 to the pool with allocation 2 at t+20
            await advanceTimeAndBlock(9) // t+19
            await this.chef.addPool("20", this.lp2.address, "0x0000000000000000000000000000000000000000") // t+20
            // Alice's pending reward should be:    10*100*0.9 = 900 (+90) ULTI
            //                                      10*10 = 100 (+10) BONUS
            expect((await this.chef.pendingReward(0, this.alice.address)).pendingUlti).to.be.within(900 - this.tokenOffset, 990 + this.tokenOffset)
            expect((await this.chef.pendingReward(0, this.alice.address)).pendingBonus).to.be.within(100 - this.tokenOffset, 110 + this.tokenOffset)
            // Bob deposits 10 LP2s at t+25
            increase(duration.seconds(4)) // t+24
            await this.chef.connect(this.bob).deposit(1, "5", { from: this.bob.address }) // t+25
            // Alice's pending reward should be:    900 + 5*1/3*100*0.9 = 1050 (+90) ULTI
            //                                      100 + 5*10 = 150 (+10) BONUS
            expect((await this.chef.pendingReward(0, this.alice.address)).pendingUlti).to.be.within(1050 - this.tokenOffset, 1140 + this.tokenOffset)
            expect((await this.chef.pendingReward(0, this.alice.address)).pendingBonus).to.be.within(150 - this.tokenOffset, 160 + this.tokenOffset)
            await advanceTimeAndBlock(5) // t+30
            // Alice's pending reward should be:    1050 + 5*1/3*100*0.9 = 1200 (+90) ULTI
            //                                      150 + 5*10 = 200 (+10) BONUS
            // Bob's pending reward should be:  5*2/3*100*0.9 = 300 (+90) ULTI
            //                                  0 BONUS
            expect((await this.chef.pendingReward(0, this.alice.address)).pendingUlti).to.be.within(1200 - this.tokenOffset, 1290 + this.tokenOffset)
            expect((await this.chef.pendingReward(0, this.alice.address)).pendingBonus).to.be.within(200 - this.tokenOffset, 210 + this.tokenOffset)
            expect((await this.chef.pendingReward(1, this.bob.address)).pendingUlti).to.be.within(300 - this.tokenOffset, 390 + this.tokenOffset)
            expect((await this.chef.pendingReward(1, this.alice.address)).pendingBonus).to.equal("0")
            // Alice and Bob should not have pending rewards in pools they're not staked in
            expect((await this.chef.pendingReward(1, this.alice.address)).pendingUlti).to.equal("0")
            expect((await this.chef.pendingReward(1, this.alice.address)).pendingBonus).to.equal("0")
            expect((await this.chef.pendingReward(0, this.bob.address)).pendingUlti).to.equal("0")
            expect((await this.chef.pendingReward(0, this.bob.address)).pendingBonus).to.equal("0")

            // Make sure they have receive the same amount as what was pending
            await this.chef.connect(this.alice).withdraw(0, "10", { from: this.alice.address }) // t+31
            // Alice should have:   1200 + 1*1/3*100*0.9 = 1230 (+90) ULTI
            //                      200 + 1*10 = 210 (+10) BONUS
            expect(await this.ulti.balanceOf(this.alice.address)).to.be.within(1230 - this.tokenOffset, 1320 + this.tokenOffset)
            expect(await this.bonusReward.balanceOf(this.alice.address)).to.be.within(210 - this.tokenOffset, 220 + this.tokenOffset)
            await this.chef.connect(this.bob).withdraw(1, "5", { from: this.bob.address }) // t+32
            // Bob should have: 300 + 2*2/3*100*0.9 = 420 (+90) ULTI
            //                  0 BONUS
            expect(await this.ulti.balanceOf(this.bob.address)).to.be.within(420 - this.tokenOffset, 510 + this.tokenOffset)
            expect(await this.bonusReward.balanceOf(this.bob.address)).to.equal("0")
        })

        after(async function () {
            await network.provider.request({
                method: "hardhat_reset",
                params: [],
            })
        })
    })
})