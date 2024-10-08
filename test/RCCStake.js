const { expect } = require("chai"); 
const {ethers} = require("hardhat"); 
// const web3 = require("@nomic");

describe("RCCStake", function () { 
    let rccStake;
    let owner;

    before(async () => { 
        const [owner] = await ethers.getSigners();

        // ⽣成合约实例并且复⽤ 
        // rccStake = await hardhat.ethers.deployContract("RCCStake", []); 
        const RCCStake = await ethers.getContractFactory("RCCStake");

        rccStake = await RCCStake.deploy();
        await rccStake.waitForDeployment();

        console.log("Deploying contracts with the account:", owner.address);

        const RCC_ADDRESS = "0xb002f38B4C3A7f8E158Ab752A71dBE2C33358d48";//替换为你的 RCC token 地址
        const START_BLOCK = 0;
        const END_BLOCK = 100000;
        const RCC_PER_BLOCK = BigInt(1 * (10 ** 18));//1 ether 单位

        const tx = await rccStake.initialize(RCC_ADDRESS, START_BLOCK, END_BLOCK, RCC_PER_BLOCK);
        await tx.wait();

        console.log("RCCStake contract deployed to:", await rccStake.getAddress());
    }); 

    it("rccStake add pools success", async function () { 
        const blockNumber = await ethers.provider.getBlockNumber();
        console.log("Current block number:", blockNumber);

        const zeroAddress = ethers.ZeroAddress;

        expect(await rccStake.addPool(zeroAddress, 100, 1, 100, true))
        .to.emit(rccStake, "AddPool")
        .withArgs(zeroAddress, 100, blockNumber + 1, 1, 100);
    }); 

});