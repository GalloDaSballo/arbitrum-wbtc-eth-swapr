import pytest
from brownie import (
    MyStrategy,
    SettV3,
    Controller,
)


@pytest.fixture()
def old_strategy():
    return MyStrategy.at("0x43942cEae98CC7485B48a37fBB1aa5035e1c8B46")


@pytest.fixture()
def vault():
    return SettV3.at("0xaf9aB64F568149361ab670372b16661f4380e80B")


def test_migration(
    want,
    strategy,
    old_strategy,
    vault,
):
    # Verify want
    assert want == strategy.want() == old_strategy.want() == vault.token()
    assert old_strategy.controller() == vault.controller()

    governance = old_strategy.governance()

    # ==== Parameter comparison ==== #
    # Check that strategy's constants remain the same
    assert strategy.reward() == old_strategy.reward()
    assert strategy.badgerTree() == old_strategy.badgerTree()

    # Check that strategy's parameters remain the same
    assert strategy.stakingContract() == old_strategy.stakingContract()
    assert (
        strategy.autocompoundOnWithdrawAll() == old_strategy.autocompoundOnWithdrawAll()
    )
    assert (
        strategy.performanceFeeGovernance() == old_strategy.performanceFeeGovernance()
    )
    assert (
        strategy.performanceFeeStrategist() == old_strategy.performanceFeeStrategist()
    )
    assert strategy.withdrawalFee() == old_strategy.withdrawalFee()

    assert strategy.performanceFeeGovernance() == old_strategy.performanceFeeGovernance()
    assert strategy.performanceFeeStrategist() == old_strategy.performanceFeeStrategist()
    assert strategy.withdrawalFee() == old_strategy.withdrawalFee()

    # ==== Pre-Migration checks ==== #

    # Balance of Sett (Balance on Sett, Controller and Strategy) is greater than 0
    initialSettBalance = vault.balance()
    assert initialSettBalance > 0
    # Balance of vault equals to the Sett's balance minus strategy balance
    assert want.balanceOf(vault.address) + old_strategy.balanceOf() == initialSettBalance
    # Balance of new Strategy starts off at 0
    assert strategy.balanceOf() == 0
    # PPFS before migration
    ppfs = vault.getPricePerFullShare()

    # ==== Migration ==== #
    migrate_strategy(
        old_strategy,
        strategy,
        governance,
    )

    # ==== Post-Migration checks ==== #

    # Balance of Sett remains the same
    assert initialSettBalance == vault.balance()
    # Balance of vault equals to the whole Sett balance since controller withdraws all of want
    # and this is transfered to the vault.
    assert want.balanceOf(vault.address) == initialSettBalance
    # Balance of old Strategy goes down to 0
    assert old_strategy.balanceOf() == 0
    # Balance of new Strategy starts off at 0
    assert strategy.balanceOf() == 0
    # PPS remain the same post migration
    assert ppfs == vault.getPricePerFullShare()

    # Earn
    vault.earn({"from": governance})

    # Balance of Sett remains the same
    assert vault.balance() == initialSettBalance
    assert want.balanceOf(vault.address) + strategy.balanceOf() == initialSettBalance


def migrate_strategy(old_strategy, new_strategy, governance):
    want = old_strategy.want()
    controller = Controller.at(old_strategy.controller())

    # Verify want
    assert old_strategy.want() == new_strategy.want()

    # Set new strategy controller
    new_strategy.setController(controller.address, {"from": governance})

    # Approve new strategy for want on Controller
    controller.approveStrategy(want, new_strategy.address, {"from": governance})
    assert controller.approvedStrategies(want, new_strategy.address)

    # Set new strategy for want on Controller
    controller.setStrategy(want, new_strategy.address, {"from": governance})
    assert controller.strategies(want) == new_strategy.address
