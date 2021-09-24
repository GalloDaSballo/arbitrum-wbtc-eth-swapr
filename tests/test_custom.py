import brownie
from brownie import *
from helpers.constants import MaxUint256
from helpers.SnapshotManager import SnapshotManager
from helpers.time import days

"""
  TODO: Put your tests here to prove the strat is good!
  See test_harvest_flow, for the basic tests
  See test_strategy_permissions, for tests at the permissions level
"""


def test_my_custom_test(deployer, sett, strategy, want):
    old_staking_contract = strategy.stakingContract()

    new_staking = "0x79ba8b76F61Db3e7D994f7E384ba8f7870A043b7" ## Random Address

    with brownie.reverts("onlyGovernance"):
      strategy.setStakingContract(new_staking, {"from": deployer}) 

    governance = accounts.at(strategy.governance(), force=True)
    strategy.setStakingContract(new_staking, {"from": governance}) 

    # assert strategy.stakingContract() != old_staking_contract ## We can't test as we don't have a second staking cotnract

