-include .env

# deps
update:; forge update
build  :; forge build
size  :; forge build --sizes

# storage inspection
inspect :; forge inspect ${contract} storage-layout --pretty

# specify which fork to use. set this in our .env
# if we want to test multiple forks in one go, remove this as an argument below
FORK_URL := ${TEST_RPC_URL} # BASE_RPC_URL, ETH_RPC_URL, ARBITRUM_RPC_URL
PRIVATE_KEY := ${PRIVATE_KEY}

# if we want to run only matching tests, set that here
test := test_

# Declare PHONY targets
.PHONY: test update build size inspect trace gas test-contract trace-contract test-test trace-test snapshot snapshot-diff trace-setup trace-max coverage coverage-report coverage-debug clean format format-check coverage-html

# local tests without fork
test :; forge test -vv --fork-url ${FORK_URL}
trace :; forge test -vvv --fork-url ${FORK_URL}
gas :; forge test --fork-url ${FORK_URL} --gas-report
test-contract :; forge test -vv --match-contract $(contract) --fork-url ${FORK_URL}
test-contract-gas :; forge test --gas-report --match-contract ${contract} --fork-url ${FORK_URL}
trace-contract :; forge test -vvv --match-contract $(contract) --fork-url ${FORK_URL}
test-test :; forge test -vv --match-test $(test) --fork-url ${FORK_URL}
test-test-trace :; forge test -vvv --match-test $(test) --fork-url ${FORK_URL}
trace-test :; forge test -vvvvv --match-test $(test) --fork-url ${FORK_URL}
snapshot :; forge snapshot -vv --fork-url ${FORK_URL}
snapshot-diff :; forge snapshot --diff -vv --fork-url ${FORK_URL}
trace-setup :; forge test -vvvv --fork-url ${FORK_URL}
trace-max :; forge test -vvvvv --fork-url ${FORK_URL}
coverage :; forge coverage --fork-url ${FORK_URL}
coverage-report :; forge coverage --report lcov --fork-url ${FORK_URL}
coverage-debug :; forge coverage --report debug --fork-url ${FORK_URL}

clean :; forge clean
format :; forge fmt
format-check :; forge fmt --check

deploy :; forge script script/Deploy.s.sol:DeployScript --rpc-url ${FORK_URL} --private-key ${PRIVATE_KEY} --broadcast

coverage-html:
	@echo "Running coverage..."
	forge coverage --report lcov --fork-url ${FORK_URL}
	@if [ "`uname`" = "Darwin" ]; then \
		lcov --ignore-errors inconsistent --remove lcov.info 'script/*' --output-file lcov.info; \
		genhtml --ignore-errors inconsistent -o coverage-report lcov.info; \
	else \
		lcov --remove lcov.info 'script/*' --output-file lcov.info; \
		genhtml -o coverage-report lcov.info; \
	fi
	@echo "Coverage report generated at coverage-report/index.html"
