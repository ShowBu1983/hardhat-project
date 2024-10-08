const {ethers} = require('hardhat');

async function main() {
    console.log("Deploying contract...");

    const [owner] = await ethers.getSigners();

    console.log("Deploying contracts with the account:", owner.address);

    const RCCStake = await ethers.getContractFactory("RCCStake");

    const RCC_ADDRESS = "0xb002f38B4C3A7f8E158Ab752A71dBE2C33358d48";//替换为你的 RCC token 地址
    const START_BLOCK = 0;
    const END_BLOCK = 100000;
    const RCC_PER_BLOCK = BigInt(1 * (10 ** 18));//1 ether 单位

    const rccStake = await RCCStake.deploy();
    await rccStake.waitForDeployment();

    const tx = await rccStake.initialize(RCC_ADDRESS, START_BLOCK, END_BLOCK, RCC_PER_BLOCK);
    await tx.wait();

    console.log("RCCStake contract deployed to:", await rccStake.getAddress());
}

main()
.then(()=>process.exit(0))
.catch(error =>{
    console.error("error deploy : ", error);
    process.exit(1);
});