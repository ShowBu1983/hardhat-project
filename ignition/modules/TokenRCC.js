const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules"); 

module.exports = buildModule("TokenRCCModule", (m) => { 
    const TokenRCC = m.contract("TokenRCC", [1000]); 
    return { TokenRCC }; 
}); 