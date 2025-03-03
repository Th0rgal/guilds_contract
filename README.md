# Shared Wallet
A shared wallet contract implementation on Starknet.

_Disclaimer: This code is not intended for production use and has not been audited or tested thoroughly. This is just an initial experiment_

## Description
This project provides the following:

- Contracts that acts as an infinite token fund with ERC20 and ERC721 share implemntations.
  - Accepts an array of owners owners that can add and remove from the fund
  - Accepts an array of tokens for the fund composition
  - Accepts an array of weights for the balance of this composition
  - Function that allows deposits of funds and distributes shares
  - Function that allows withdrawal of funds according to the shares held
- Contracts that implements governance mechanisms for porposing fund allocation - ***TBD***
- Contract that handles incentivisation for positive return proposals for the fund - ***TBD***

## Setup

```
python3.7 -m venv venv
source venv/bin/activate
python -m pip install cairo-nile
nile install
```

## Acknowledgements

[perama](https://twitter.com/eth_worm) for their notes on [Cairo](https://perama-v.github.io/cairo/intro/)

[sambarnes](https://twitter.com/__________sam__), for their work on [cairo-dutch](https://github.com/sambarnes/cairo-dutch), used for openzeppelin account compatible signing logic
