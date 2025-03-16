#!/bin/bash

set -e

: ${NOPROMPT=false}

unset CODESPACES
unset GITHUB_TOKEN

msg() {
	echo ">>> $*" >&2
}

run() {
	msg "Running: $@"
	"$@"
}

confirm() {
	if $NOPROMPT; then
		return
	fi
	read -p ">>> Continue? [y/N] " -n 1 -r >&2
	echo >&2
	case "$REPLY" in
		y) return ;;
	esac
	exit 1
}

enable_remote_env() {
	msg 'Updating ~/.azd/config.yaml to enable the azd remote env'
	confirm
	run azd config set state.remote.backend AzureBlobStorage
	run azd config set state.remote.config.accountName $1
}

disable_remote_env() {
	msg 'Updating ~/.azd/config.yaml to disable the azd remote env'
	confirm
	run azd config unset state
}

cmd_auth_config() {
	run azd config set auth.useAzCliAuth true
}

cmd_auth_az() {
	AZD_INPUTS_FILE=".github/azdops/inputs.yml"
	AZD_REMOTE_FILE=".github/azdops/remote.yml"
	eval $(npx -y js-yaml "$AZD_INPUTS_FILE" | jq -r 'to_entries|map("\(.key)=\(.value)")|.[]')
	eval $(npx -y js-yaml "$AZD_REMOTE_FILE" | jq -r 'to_entries|map("\(.key)=\(.value)")|.[]')

	AZURE_TEMP_DIR=$(mktemp -d)
	export AZURE_CONFIG_DIR=$AZURE_TEMP_DIR
	msg "Logging in with Azure CLI as user (saved in $AZURE_CONFIG_DIR)"
	run az config set --only-show-errors core.login_experience_v2=off
	run az login -t=$AZURE_TENANT_ID >/dev/null
	run az account set -s $AZURE_SUBSCRIPTION_ID
	run az account show
	UPN=$(run az account show --query user.name -o tsv)
	run az keyvault set-policy -n $AZD_REMOTE_ENV_KEY_VAULT_NAME --secret-permissions all purge --certificate-permissions all purge --upn $UPN -o none

	PASSWORD=$(run az keyvault secret show --vault-name $AZD_REMOTE_ENV_KEY_VAULT_NAME --name AZURE-CLIENT-SECRET --query value -o tsv || true)

	msg "Deleting the temporary directory"
	run rm -rf $AZURE_TEMP_DIR

	if test -z "$PASSWORD"; then
		msg "E: Failed to get the password from the key vault: run ./azdops.sh auth-az-secret"
		exit 1
	fi

	msg "Logging in with Azure CLI as service principal"
	unset AZURE_CONFIG_DIR
	echo -n "$PASSWORD" | run az login --service-principal -u $AZURE_CLIENT_ID -t $AZURE_TENANT_ID -p @/dev/stdin -o none
	run az account set -s $AZURE_SUBSCRIPTION_ID
	run az account show
}

cmd_auth_az_secret() {
	AZD_INPUTS_FILE=".github/azdops/inputs.yml"
	AZD_REMOTE_FILE=".github/azdops/remote.yml"
	eval $(npx -y js-yaml "$AZD_INPUTS_FILE" | jq -r 'to_entries|map("\(.key)=\(.value)")|.[]')
	eval $(npx -y js-yaml "$AZD_REMOTE_FILE" | jq -r 'to_entries|map("\(.key)=\(.value)")|.[]')

	if test -n "$AZURE_CLIENT_SECRET"; then
		msg "Using the provided secret in AZURE_CLIENT_SECRET"
		PASSWORD=$AZURE_CLIENT_SECRET
	else
		msg "Creating new secret for the app $AZURE_CLIENT_ID"
		DISPLAY_NAME="$AZD_REMOTE_ENV_NAME $AZD_REMOTE_ENV_KEY_VAULT_NAME $(date -u +%Y-%m-%dT%H:%M:%SZ)"
		PASSWORD=$(run az ad app credential reset --only-show-errors --id $AZURE_CLIENT_ID --append --display-name "$DISPLAY_NAME" --end-date 2299-12-31 --query password --output tsv)
	fi
	echo -n "$PASSWORD" | run az keyvault secret set --vault-name $AZD_REMOTE_ENV_KEY_VAULT_NAME --name AZURE-CLIENT-SECRET --file /dev/stdin -o none
}

cmd_auth_gh() {
	run gh auth login "$@"
}

cmd_load() {
	if test -z "$AZD_REMOTE_ENV_STORAGE_ACCOUNT_NAME" -o -z "$AZD_REMOTE_ENV_NAME"; then
		AZD_REMOTE_FILE=".github/azdops/remote.yml"
		if test -r "$AZD_REMOTE_FILE"; then
			eval $(npx -y js-yaml "$AZD_REMOTE_FILE" | jq -r 'to_entries|map("\(.key)=\(.value)")|.[]')
		fi
	fi
	if test -z "$AZD_REMOTE_ENV_STORAGE_ACCOUNT_NAME"; then
		msg 'E: AZD_REMOTE_ENV_STORAGE_ACCOUNT_NAME is not set in the local env'
		exit 1
	fi
	enable_remote_env $AZD_REMOTE_ENV_STORAGE_ACCOUNT_NAME
	if test -n "$AZD_REMOTE_ENV_NAME"; then
		run azd env select $AZD_REMOTE_ENV_NAME
	fi
	run azd env list
}

cmd_save() {
	if ! eval $(azd env get-values); then
		msg 'E: Failed to get values from the azd local env'
		exit 1
	fi
	if test -z "$AZURE_STORAGE_ACCOUNT_NAME"; then
		msg 'E: AZURE_STORAGE_ACCOUNT_NAME is not set in the azd local env'
		exit 1
	fi
	enable_remote_env $AZURE_STORAGE_ACCOUNT_NAME
	run azd env refresh
	run azd env list
}

cmd_set() {
	if ! eval $(azd env get-values); then
		msg 'E: Failed to get values from the azd local env'
		exit 1
	fi
	if test -z "$AZURE_STORAGE_ACCOUNT_NAME"; then
		msg 'E: AZURE_STORAGE_ACCOUNT_NAME is not set in the azd local env'
		exit 1
	fi
	run gh variable set AZD_REMOTE_ENV_NAME -b $AZURE_ENV_NAME
	run gh variable set AZD_REMOTE_ENV_STORAGE_ACCOUNT_NAME -b $AZURE_STORAGE_ACCOUNT_NAME
	run gh secret set AZD_REMOTE_ENV_NAME -b $AZURE_ENV_NAME -a codespaces
	run gh secret set AZD_REMOTE_ENV_STORAGE_ACCOUNT_NAME -b $AZURE_STORAGE_ACCOUNT_NAME -a codespaces
}

cmd_clear() {
	disable_remote_env
	run azd env list
}

cmd_help() {
	msg "Usage: $0 <command> [options...] [args...]"
	msg "Options:"
	msg "  --help,-h      - Show this help"
	msg "  --no-prompt    - Do not ask for confirmation"
	msg "Commands:"
	msg "  auth-config    - Run \"azd config set auth.useAzCliAuth true\""
	msg "  auth-az        - Run \"az login\""
	msg "  auth-az-secret - Reset Azure client secret and save it in key vault"
	msg "  auth-gh        - Run \"gh auth login\""
	msg "  load           - Load the azd remote env"
	msg "  save           - Save the azd remote env"
	msg "  set            - Set GitHub secrets for the azd remote env"
	msg "  clear          - Clear the azd remote env"
	exit $1
}

OPTIONS=$(getopt -o h -l help,no-prompt -- "$@")
if test $? -ne 0; then
	cmd_help 1
fi

eval set -- "$OPTIONS"

while true; do
	case "$1" in
		-h|--help)
			cmd_help 0
			;;
		--no-prompt)
			NOPROMPT=true
			shift
			;;
		--)
			shift
			break
			;;
		*)
			msg "E: Invalid option: $1"
			cmd_help 1
			;;
	esac
done

if test $# -eq 0; then
	msg "E: Missing command"
	cmd_help 1
fi

case "$1" in
	auth-config)
		shift
		cmd_auth_config "$@"
		;;
	auth-az)
		shift
		cmd_auth_az "$@"
		;;
	auth-az-secret)
		shift
		cmd_auth_az_secret "$@"
		;;
	auth-gh)
		shift
		cmd_auth_gh "$@"
		;;
	load)
		shift
		cmd_load "$@"
		;;
	save)
		shift
		cmd_save "$@"
		;;
	set)
		shift
		cmd_set "$@"
		;;
	clear)
		shift
		cmd_clear "$@"
		;;
	*)
		msg "E: Invalid command: $1"
		cmd_help 1
		;;
esac