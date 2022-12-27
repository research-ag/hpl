import R "mo:base/Result";
import AssocList "mo:base/AssocList";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Option "mo:base/Option";
import C "../shared/constants";

module {
  // the following constants are defined as a means of DoS-protection
  public let constants = {
    // maximum number of contributions allowed per tx
    maxContributions = 256;

    // maximum number of inflows and outflows allowed per contribution 
    // TODO: think of limiting only total flows per tx, not per contribution
    maxFlows = 256;

    // maximum allowed memo size in bytes
    maxMemoBytes = 256;
    
    // maximum value for the subaccount id allowed in a flow
    maxSubaccounts = C.maxSubaccounts;
    
    // maximum value for the virtual account id allowed in a flow
    maxVirtualAccounts = C.maxVirtualAccounts;

    // maxmium value for the asset id allowed in an #ft flow
    maxAssets = C.maxAssets;

    // maximum value for the quantity allowed in an #ft flow, equals 2**128
    maxFtUnits = 340282366920938463463374607431768211456;
  };

  public type SubaccountId = Nat;
  public type VirtualAccountId = Nat;
  // for #sub, we need only id of the subaccount;
  // for #vir, we need an id of virtual account + remote principal in this subaccount, so we can make approvement logic on aggregator size.
  // if provide wrong remote principal, the ledger will reject the transaction
  // note that for #vir transactions, contribution owner should be the remotePrincipal of the virtual account, and principal inside #vir uuple is the owner of virtual account
  public type AccountReference = { #sub: SubaccountId; #vir: (Principal, VirtualAccountId) };
  public type AssetId = Nat;
  public type Asset = { 
    #ft : (id : AssetId, quantity : Nat);
  };
  // TODO re-check size estimation logic
  public type Contribution = {
    owner : Principal;
    inflow : [(AccountReference, Asset)];
    outflow : [(AccountReference, Asset)];
    mints : [Asset];
    burns : [Asset];
    memo : ?Blob
  };
  // inflow/outflow encodes a map subaccount -> asset list
  // subaccount id must be strictly increasing throughout the list to rule out duplicate keys

  // Tx = Transaction
  // map is seen as a map from a principal to its contribution
  // the owner principals in each contribution must be strictly increasing throughout the list to rule out duplicate keys
  public type Tx = {
    map : [Contribution]
  };

  public type Batch = [Tx];
  public type AssetError = {
    #AssetIdTooLarge;
    #FtQuantityTooLarge
  };
  public type FlowError = AssetError or {
    #SubaccountIdTooLarge;
    #VirtualAccountIdTooLarge;
  };
  public type ContributionError = FlowError or {
    #MemoTooLarge;
    #TooManyFlows;
  };
  public type TxError = ContributionError or { 
    #TooManyContributions;
    #NonZeroAssetSum;
  };

  type Result<X,Y> = R.Result<X,Y>;

  func nFlows(c : Contribution) : Nat =
    c.mints.size() + c.burns.size() + c.inflow.size() + c.outflow.size();

  // Tx size in bytes
  public func size(tx : Tx) : Nat {
    let contributions = tx.map.size(); 
    var flows = 0;
    for (c in tx.map.vals()) {
      flows += nFlows(c);
    };
    contributions * 34 + flows * 29
  }; 

  func owners(tx : Tx) : [Principal] = 
    Array.map(tx.map, func(c : Contribution) : Principal {c.owner});

  func validateAsset(a : Asset) : Result<(), AssetError> {
    switch a {
      case (#ft(id, quantity)) {
        if (id >= constants.maxAssets) {
          return #err(#AssetIdTooLarge)
        };
        if (quantity >= constants.maxFtUnits) {
          return #err(#FtQuantityTooLarge)
        }
      }
    };
    return #ok
  };

  func validateFlow(f : (AccountReference, Asset)) : Result<(), FlowError> {
    switch(f.0) {
      case (#sub saf) {
        if (saf >= constants.maxSubaccounts) {
          return #err(#SubaccountIdTooLarge)
        };
      };
      case (#vir vaf) {
        if (vaf.1 >= constants.maxVirtualAccounts) {
          return #err(#VirtualAccountIdTooLarge)
        };
      };
    };
    validateAsset(f.1);
  };

  func validateContribution(c : Contribution) : Result<(), ContributionError> {
    // memo size
    switch (c.memo) {
      case (?m) {
        if (m.size() > constants.maxMemoBytes) {
          return #err(#MemoTooLarge)
        }
      };
      case (_) {}
    };
    // number of flows
    if (nFlows(c) > constants.maxFlows) {
      return #err(#TooManyFlows);
    };
    // validate assets (mint/burn) in isolation
    for (a in c.mints.vals()) {
      switch (validateAsset(a)) {
        case (#err e) { return #err e };
        case (_) {}
      }
    };
    for (a in c.burns.vals()) {
      switch (validateAsset(a)) {
        case (#err e) { return #err e };
        case (_) {}
      }
    };
    // validate flows (inflow/outflow) in isolation
    for (f in c.inflow.vals()) {
      switch (validateFlow(f)) {
        case (#err e) { return #err e };
        case (_) {}
      }
    };
    for (f in c.outflow.vals()) {
      switch (validateFlow(f)) {
        case (#err e) { return #err e };
        case (_) {}
      }
    };
    #ok
  };

  // validate tx, error describes why it is not valid
  public func validate(tx: Tx): Result<(), TxError> {
    // number of contributions
    if (tx.map.size() > constants.maxContributions) {
      return #err(#TooManyContributions);
    };
    // validate each contribution in isolation
    for (c in tx.map.vals()) {
      switch (validateContribution(c)) {
        case (#err e) { return #err e };
        case (_) {}
      }
    };

    // equilibrium of flows 
    var balanceMap : AssocList.AssocList<AssetId, Int> = null;
    func add(a : Asset) {
      switch a {
        case (#ft (id, quantity)) {
          let newValue = Option.get(AssocList.find(balanceMap, id, Nat.equal),0) + quantity;
          balanceMap := AssocList.replace(balanceMap, id, Nat.equal, ?newValue).0;
        };
      };
    };
    func sub(a : Asset) {
      switch a {
        case (#ft (id, quantity)) {
          let newValue = Option.get(AssocList.find(balanceMap, id, Nat.equal),0) - quantity;
          balanceMap := AssocList.replace(balanceMap, id, Nat.equal, ?newValue).0;
        };
      };
    };
    // build map
    for (contribution in tx.map.vals()) {
      for (a in contribution.mints.vals()) { add(a); };
      for (a in contribution.burns.vals()) { sub(a); };
      for (f in contribution.outflow.vals()) { add(f.1); };
      for (f in contribution.inflow.vals()) { sub(f.1); };
    };
    // test if map has negative entries
    func cons(_ : Nat, quantity : Int, res : Bool) : Bool = res or (quantity < 0);
    if (AssocList.fold(balanceMap, false, cons)) {
      return #err(#NonZeroAssetSum); 
    };
    // everything passed, tx is ok
    #ok
  }
}
