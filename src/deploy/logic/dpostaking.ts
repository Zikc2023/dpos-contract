import { HardhatRuntimeEnvironment } from 'hardhat/types';

const deploy = async ({ getNamedAccounts, deployments }: HardhatRuntimeEnvironment) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('DPoStakingLogic', {
    contract: 'DPoStaking',
    from: deployer,
    log: true,
  });
};

deploy.tags = ['DPoStakingLogic'];
deploy.dependencies = ['ProxyAdmin'];

export default deploy;
