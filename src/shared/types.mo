module {
  public type AggregatorId = Nat;

  // transaction ids
  public type LocalId = Nat;
  public type GlobalId = ( aggregator: AggregatorId, local_id: LocalId );

}
