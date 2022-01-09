import hre from "hardhat";

import {
  FLOKI,
  FLOKI__factory,
  StaticTaxHandler,
  StaticTaxHandler__factory,
  TreasuryHandlerAlpha,
  TreasuryHandlerAlpha__factory,
  ZeroTaxHandler,
  ZeroTaxHandler__factory,
  ZeroTreasuryHandler,
  ZeroTreasuryHandler__factory,
} from "../types";

async function main(): Promise<void> {
  const name = "NHAM-Test-02";
  const routerAddress = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

  const signers = await hre.ethers.getSigners();
  const signer = signers[0];

  const Floki: FLOKI__factory = await hre.ethers.getContractFactory("FLOKI");
  const StaticTaxHandler: StaticTaxHandler__factory = await hre.ethers.getContractFactory("StaticTaxHandler");
  const TreasuryHandlerAlpha: TreasuryHandlerAlpha__factory = await hre.ethers.getContractFactory(
    "TreasuryHandlerAlpha",
  );
  const ZeroTaxHandler: ZeroTaxHandler__factory = await hre.ethers.getContractFactory("ZeroTaxHandler");
  const ZeroTreasuryHandler: ZeroTreasuryHandler__factory = await hre.ethers.getContractFactory("ZeroTreasuryHandler");

  const zeroTaxHandler: ZeroTaxHandler = await ZeroTaxHandler.deploy();
  const zeroTreasuryHandler: ZeroTreasuryHandler = await ZeroTreasuryHandler.deploy();

  const floki: FLOKI = await Floki.deploy(name, name, zeroTaxHandler.address, zeroTreasuryHandler.address);
  const staticTaxHandler: StaticTaxHandler = await StaticTaxHandler.deploy();
  const treasuryHandlerAlpha: TreasuryHandlerAlpha = await TreasuryHandlerAlpha.deploy(
    signer.address,
    floki.address,
    routerAddress,
  );

  await floki.setTaxHandler(staticTaxHandler.address);
  await floki.setTreasuryHandler(treasuryHandlerAlpha.address);

  // Sleep for 5 minutes to give the network enough time.
  await new Promise(resolve => setTimeout(resolve, 5000));

  try {
    await hre.run("verify:verify", {
      address: zeroTaxHandler.address,
      constructorArguments: [],
    });
  } catch (e) {
    console.log(e);
  }

  try {
    await hre.run("verify:verify", {
      address: zeroTreasuryHandler.address,
      constructorArguments: [],
    });
  } catch (e) {
    console.log(e);
  }

  try {
    await hre.run("verify:verify", {
      address: floki.address,
      constructorArguments: [name, name, zeroTaxHandler.address, zeroTreasuryHandler.address],
    });
  } catch (e) {
    console.log(e);
  }

  try {
    await hre.run("verify:verify", {
      address: staticTaxHandler.address,
      constructorArguments: [],
    });
  } catch (e) {
    console.log(e);
  }

  try {
    await hre.run("verify:verify", {
      address: treasuryHandlerAlpha.address,
      constructorArguments: [signer.address, floki.address, routerAddress],
    });
  } catch (e) {
    console.log(e);
  }
}

// We recommend this pattern to be able to use async/await everywhere and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
