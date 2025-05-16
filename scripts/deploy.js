const { ethers } = require("hardhat");

async function main() {
  console.log("Deploying DeFi Lending Protocol to Core Testnet 2...");

  // We need a mock token for the lending protocol
  // In a real scenario, you would use an existing token address
  const MockToken = await ethers.getContractFactory("MockToken");
  const mockToken = await MockToken.deploy("Mock Token", "MTK");
  await mockToken.deployed();
  
  console.log(`MockToken deployed to: ${mockToken.address}`);

  // Deploy the lending protocol with the mock token
  const DeFiLendingProtocol = await ethers.getContractFactory("DeFiLendingProtocol");
  const lendingProtocol = await DeFiLendingProtocol.deploy(mockToken.address);
  await lendingProtocol.deployed();

  console.log(`DeFiLendingProtocol deployed to: ${lendingProtocol.address}`);
  console.log("Deployment completed successfully!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
