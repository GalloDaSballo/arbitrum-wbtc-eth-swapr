## Ideally, they have one file with the settings for the strat and deployment
## This file would allow them to configure so they can test, deploy and interact with the strategy

BADGER_DEV_MULTISIG = "0x468A0FF843BC5D185D7B07e4619119259b03619f"

WANT = "0x9A17D97Fb5f76F44604270448Ac77D55Ac40C15c"  ## WBTC/WETH swaprLP
LP_COMPONENT = (
    "0x79ba8b76F61Db3e7D994f7E384ba8f7870A043b7"  ## WBTC/WETH Staking Contract
)
REWARD_TOKEN = "0xdE903E2712288A1dA82942DDdF2c20529565aC30"  ## AAVE Token

PROTECTED_TOKENS = [WANT, LP_COMPONENT, REWARD_TOKEN]
## Fees in Basis Points
DEFAULT_GOV_PERFORMANCE_FEE = 1000
DEFAULT_PERFORMANCE_FEE = 1000
DEFAULT_WITHDRAWAL_FEE = 50

FEES = [DEFAULT_GOV_PERFORMANCE_FEE, DEFAULT_PERFORMANCE_FEE, DEFAULT_WITHDRAWAL_FEE]

REGISTRY = "0xFda7eB6f8b7a9e9fCFd348042ae675d1d652454f"  # Multichain BadgerRegistry
