# Cronos Chain Mainnet

These sample `app.toml` and `config.toml` files serve as a basis for an archive node with RocksDB to setup.
Note that the `moniker`,` persistent_peers`,` external_address `,` unconditional_peer_ids` in `config.toml` need to be filled in.


## Pruning
Other common node types include running a `pruned` node by setting:
- `PruneDefault = NewPruningOptions(362880, 100, 10)` for default pruning or
- `everything` if you only need to do transaction broadcasting and only need the last blocks.


## DB backend
Instead of the more performant rocksdb, you can also opt for the default golevelsdb db backend.
- `db_backend = "goleveldb"` in `config.toml`
- `app-db-backend = "goleveldb"` in `app.toml`

for more info, check the cronos docs:
https://docs.cronos.org/for-node-hosts/running-nodes/cronos-node-best-practises