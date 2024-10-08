const {ethers} = require('hardhat');

async function main(){
    console.log("Deploying contract...");

    const TokenRCC = await ethers.deployContract("TokenRCC", [1000]);

    await TokenRCC.waitForDeployment();

    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    let totalSupply = TokenRCC.balanceOf(deployer.address);
    console.log("totalSupply : ", totalSupply);
    
    console.log("TokenRCC contract deployed to:", TokenRCC.target);
}

main()
.then(()=>process.exit(0))
.catch(err=>{
    console.log("deploy err :", err);
    process.exit(1);
})