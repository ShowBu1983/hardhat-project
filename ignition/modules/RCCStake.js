const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules"); 

const RCCStake = buildModule("RCCStakeModule", (m) => {
    const tokenAddress = m.getParameter("tokenAddress");
    const initialRate = m.getParameter("initialRate");

    console.log("Deploying RCCStake with parameters:");
    console.log("Token Address:", tokenAddress);
    console.log("Initial Rate:", initialRate);

    const rccStake = m.contract("RCCStake", [tokenAddress, initialRate]);

    return { rccStake };
});