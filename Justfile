set dotenv-load

chain := env_var_or_default("CHAIN", "mainnet")
deploy_script_name := if chain == "mainnet" {
    "DeployMainnet"
} else if chain == "hoodi" {
    "DeployHoodi"
} else {
    error("Unsupported chain " + chain)
}

deploy_script_path := "script" / deploy_script_name + ".s.sol:" + deploy_script_name

anvil_host := env_var_or_default("ANVIL_IP_ADDR", "127.0.0.1")
anvil_port := "8545"
anvil_rpc_url := "http://" + anvil_host + ":" + anvil_port

default: clean build

build *args:
    forge build --force {{args}}

clean:
    forge clean
    rm -rf cache broadcast out

# Deployment commands
deploy *args:
    forge script {{deploy_script_path}} --rpc-url {{anvil_rpc_url}} --broadcast --slow {{args}}

deploy-live *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    ARTIFACTS_DIR=./artifacts/latest/ just _deploy-live {{args}}

    mkdir -p ./artifacts/latest/
    cp ./broadcast/{{deploy_script_name}}.s.sol/`cast chain-id --rpc-url=$RPC_URL`/run-latest.json \
        ./artifacts/latest/transactions.json

deploy-live-no-confirm *args:
    just _warn "The current `tput bold`chain={{chain}}`tput sgr0` with the following rpc url: $RPC_URL"
    ARTIFACTS_DIR=./artifacts/latest/ just _deploy-live-no-confirm --broadcast {{args}}

    mkdir -p ./artifacts/latest/
    cp ./broadcast/{{deploy_script_name}}.s.sol/`cast chain-id --rpc-url=$RPC_URL`/run-latest.json \
        ./artifacts/latest/transactions.json

[confirm("You are about to broadcast deployment transactions to the network. Are you sure?")]
_deploy-live *args:
    just _deploy-live-no-confirm --broadcast --verify {{args}}

deploy-live-dry *args:
    just _deploy-live-no-confirm {{args}}

verify-live *args:
    just _warn "Pass --chain=your_chain manually. e.g. --chain=mainnet or --chain=hoodi"
    forge script {{deploy_script_path}} --rpc-url ${RPC_URL} --verify {{args}} --unlocked

_deploy-live-no-confirm *args:
    forge script {{deploy_script_path}} --force --rpc-url ${RPC_URL} {{args}}

_warn message:
    @tput setaf 3 && printf "[WARNING]" && tput sgr0 && echo " {{message}}"
