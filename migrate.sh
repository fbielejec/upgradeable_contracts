#!/bin/bash

set -euox pipefail

# --- SETTINGS

NODE=ws://127.0.0.1:9944

ADDRESSES_FILE=$(pwd)/addresses.json

CONTRACTS_PATH=$(pwd)

AUTHORITY=5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY
AUTHORITY_SEED=//Alice

# --- HELPER FUNCTIONS

function run_ink_dev() {
  docker start ink_dev || docker run \
                                 --network host \
                                 -v "${CONTRACTS_PATH}:/code" \
                                 -u "$(id -u):$(id -g)" \
                                 --name ink_dev \
                                 --platform linux/amd64 \
                                 --detach \
                                 --rm public.ecr.aws/p6e8q1z1/ink-dev:1.0.0 sleep 1d
}

function cargo_contract() {
  contract_dir=$(basename "${PWD}")
  docker exec \
         -u "$(id -u):$(id -g)" \
         -w "/code/$contract_dir" \
         -e RUST_LOG=info \
         ink_dev cargo contract "$@"
}

function get_address {
  local entry_name=$1
  cat $ADDRESSES_FILE | jq --raw-output ".$entry_name"
}

function get_value() {
  local contract_name=$1
  local contract_address=$2

  cd "$CONTRACTS_PATH"/$contract_name

  cargo_contract call --url "$NODE" --contract "$contract_address" --message get_value --suri "$AUTHORITY_SEED" --dry-run --output-json
}

function set_value() {
  local contract_name=$1
  local contract_address=$2
  local value=$3

  cd "$CONTRACTS_PATH"/$contract_name

  cargo_contract call --url "$NODE" --contract "$contract_address" --message set_value --args $value --suri "$AUTHORITY_SEED" --skip-confirm #--output-json
}

# --- RUN

run_ink_dev

# --- compile contracts
# ink_build rustup target add wasm32-unknown-unknown
# ink_build rustup component add rust-src

cd "$CONTRACTS_PATH"/old_a
cargo_contract build --release

cd "$CONTRACTS_PATH"/new_a
cargo_contract build --release

# --- deploy and initialize contract a

cd "$CONTRACTS_PATH"/old_a

OLD_A_CODE_HASH=$(cargo_contract upload --url "$NODE" --suri "$AUTHORITY_SEED" --output-json | jq -s . | jq -r '.[1].code_hash')
OLD_A=$(cargo_contract instantiate --url "$NODE" --constructor new --suri "$AUTHORITY_SEED" --skip-confirm --output-json | jq -r '.contract')

# OLD_A=$(get_address old_a)

# --- health checks

echo "OldA value after initialization "$(get_value old_a $OLD_A)" "

set_value old_a $OLD_A 1

echo "OldA value after set "$(get_value old_a $OLD_A)" "

# --- upload new_a contract code

cd "$CONTRACTS_PATH"/new_a
NEW_A_CODE_HASH=$(cargo_contract upload --url "$NODE" --suri "$AUTHORITY_SEED" --output-json | jq -s . | jq -r '.[1].code_hash')

# NEW_A_CODE_HASH=$(get_address new_a_code_hash)

echo "NewA code hash: "$NEW_A_CODE_HASH""

# --- set_code & migrate in one atomic transaction

cd "$CONTRACTS_PATH"/old_a

cargo_contract call --url "$NODE" --contract "$OLD_A" --message set_code --args $NEW_A_CODE_HASH "Some(0x4D475254)" --suri "$AUTHORITY_SEED" --skip-confirm

NEW_A=$OLD_A

# --- health checks

echo "NewA value after upgrade and storage migration "$(get_value new_a $NEW_A)" "

# spit adresses to a JSON file
cd "$CONTRACTS_PATH"

jq -n \
   --arg old_a_code_hash "$OLD_A_CODE_HASH" \
   --arg old_a "$OLD_A" \
   --arg new_a_code_hash "$NEW_A_CODE_HASH" \
   '{
      old_a_code_hash: $old_a_code_hash,
      old_a: $old_a,
      new_a_code_hash: $new_a_code_hash
    }' > $ADDRESSES_FILE

# --- clean up
