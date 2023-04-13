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

function get_values() {
  local contract_name=$1
  local contract_address=$2

  cd "$CONTRACTS_PATH"/$contract_name

  cargo_contract call --url "$NODE" --contract "$contract_address" --message get_values --suri "$AUTHORITY_SEED" --dry-run --output-json
}

function set_values() {
  local contract_name=$1
  local contract_address=$2
  local values=${@:3}

  cd "$CONTRACTS_PATH"/$contract_name

  cargo_contract call --url "$NODE" --contract "$contract_address" --message set_values --args $values --suri "$AUTHORITY_SEED" --skip-confirm #--output-json
}

# --- RUN

run_ink_dev

# --- compile contracts

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

echo "OldA values after initialization "$(get_values old_a $OLD_A)" "

set_values old_a $OLD_A 7 false

echo "OldA values after set "$(get_value old_a $OLD_A)" "

# --- upload new_a contract code

cd "$CONTRACTS_PATH"/new_a
NEW_A_CODE_HASH=$(cargo_contract upload --url "$NODE" --suri "$AUTHORITY_SEED" --output-json | jq -s . | jq -r '.[1].code_hash')

# NEW_A_CODE_HASH=$(get_address new_a_code_hash)

echo "NewA code hash: "$NEW_A_CODE_HASH""

# --- set_code & migrate in one atomic transaction

cd "$CONTRACTS_PATH"/old_a

cargo_contract call --url "$NODE" --contract "$OLD_A" --message set_code --args $NEW_A_CODE_HASH "None" --suri "$AUTHORITY_SEED" --skip-confirm

NEW_A=$OLD_A

# --- health checks

echo "NewA values after upgrade and storage migration "$(get_values new_a $NEW_A)" "

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
