# Account model

## Subaccounts

Subaccounts 

- can be freely opened by the owner
- have ids that are consecutively numbered
- have a fixed asset type, e.g. fungible token with asset id `n`, that cannot be changed
- are fully backed by an asset, i.e. an asset cannot be in two subaccounts at the same time
- can be accessed only by the principal that owns them where “access” means both crediting and debiting
- can not be deleted
- are tracked in the history of the ledger, i.e. all movements in and out of a subaccount are visible

**Note:** with the introduction of virtual accounts below we have removed auto-approval for receivers. It is no longer allowed to deposit directly into a subaccount without explicit approval by the owner of the subaccount. 

## Virtual accounts

Virtual accounts

- can be freely opened by the owner
- have their own id space non-overlapping with subaccount ids
- have a fixed asset type, e.g. fungible token with asset id `n`, that cannot be changed
- map to a subaccount with the same asset type which backs them, called the *backing subaccount*
- can have their mapping changed by the owner at any time
- do not have to be fully backed, i.e. the balance in the virtual account can be smaller or larger than the balance in the backing subaccount
- can have their balance set at re-set by the owner at any time
- have one defined principal, different from the owner, called the *remote principal*
- can be accessed by the remote principal where “access” means both crediting and debiting
- can be deleted, but the virtual account id cannot be re-used for a new virtual account
- are not tracked in the history of the ledger, i.e. their set up, mapping and balance adjustments are not visible, onlt the movements in the backing subaccount are

**Note:** A debit or credit is always applied to the balance of the virtual account *and* the backing subaccount. A debit only succeeds if both balances are sufficient. Therefore, a virtual account is merely a port to the backing subaccount, equipped with a guard (the remote principal). 

**Note**: a virtual account with remote principal P can be seen as

- an allowance for P to make withdrawals up to a limit which is the balance in the virtual account
- a right for P to make deposits into the backing subaccount (without P knowing which subaccount)

## Payment flow

Say A, B want to transfer funds from subaccounts  `(A,sub i)` to `(B,sub j)`. On a high level there are three options:

1. No virtual accounts are used. Funds go directly from `(A,sub i)` to `(B,sub j)` by a transaction with two contributions. Both `A` or `B` need to approve. The steps in the flow are:
    1. A submits tx to HPL, sends txid to B
    2. B reads txid from HPL to confirm the tx looks as expected
    3. B approves txid to HPL
    
    Note: 
    
    - 3 interactions with the HPL. For a canister B the query is essentially as expensive as an update call.
2. Virtual account on A’s side. The steps in the flow are:
    1. A opens a virtual account `(A, vir k)` mapping to `(A,i)` with balance `x` and remote principal `B`, sends the value `k` to B
    2. B makes a transfer from `(A, vir k)` to `(B,j)` of `x` tokens. This reduces the balance in `(A, vir k)` to 0.
    
    Note: 
    
    - 2 interactions with the HPL are required.
    - `B` makes the transfer through `processImmediateTx`, as there is only one contribution, and gets success/fail as a direct response.
    - The virtual account can be re-used for future interactions between A and B. For example, B can make refunds to A through `(A, vir k)` which will land back in `(A,sub i)`.
    - If the flow is interrupted after step a then no transfer is visible in the leger history.
3. Virtual account on B’s side. The steps in the flow are:
    1. B opens a virtual account `(B, vir l)` mapping to `(B,j)` with balance `0` and remote principal `A`, sends the value `l` to A
    2. A makes a transfer from `(A,sub i)` to `(B,vir l)` of `x` tokens
    3. B reduces the balance in  `(B,vir l)` by `x`, which will reduce it to 0
    
    Note:
    
    - 3 interactions with the HPL are required.
    - `A` makes the transfer through `processImmediateTx`, as there is only one contribution.
    - `B` gets success or fail as a direct response when reducing the balance in `(B,vir l)`.
    - The virtual account can be re-used for future interactions between A and B. For example, if B did not reduce the balance in  `(B, vir l)` or move the funds out of the backing subaccount then it means B has not accepted the funds. Then A can refund itself by taking funds out of  `(B, vir l)` again.
    - Step b is visible in the ledger history, even if the flow is interrupted after step b.

## Example: burn with flow 2

For the cycle minter burn flow we use flow 2. A is the user, B is the Minter:

1. A opens a virtual account `(A,vir k)` with B as the remote principal and balance `x`
2. A calls `burn(k,x,P)` on B
3. B transfers `x` tokens out of `(A,vir k)` to the burn account
4. If the transfer was successful then B deposits the cycles to P
5. If the deposit fails then B locally logs a credit for A 

Note:

- In the ledger history we see a transfer from a subaccount of A to the burn account.
- A could have deleted `(A, vir k)` before a refund transaction reaches the HPL. If that happens then B must log some credit for A locally.

## Example: mint with flow 2

For the cycle minter mint flow we use flow 2. A is the user, B is the Minter:

1. A opens a virtual account `(A,vir k)` with B as the remote principal and balance 0
2. P calls `mint(A,k)` on B with x cycles attached
3. B transfers `x` tokens from the mint account to `(A, vir k)`
4. If the transfer fails then B locally logs a credit for P

Note:

- In the ledger history we see a transfer from the mint account to a subaccount of A.