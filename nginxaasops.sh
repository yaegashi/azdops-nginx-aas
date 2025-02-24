#!/bin/bash

set -e

eval $(azd env get-values)

: ${NOPROMPT=false}
: ${VERBOSE=false}
: ${AZ_ARGS="-g $AZURE_RESOURCE_GROUP_NAME -n $AZURE_APP_NAME"}
: ${AZ_REVISION=}
: ${AZ_REPLICA=}
: ${AZ_CONTAINER=nginx}

NL=$'\n'

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
		[yY]) return
	esac
	exit 1
}

app_hostnames() {
	az webapp show $AZ_ARGS --query hostNames -o tsv | grep -v 'azurewebsites\.net$'
}

cmd_meid_redirect() {
	HOSTS=$(app_hostnames)
	URIS=$(az ad app show --id $MS_CLIENT_ID --query web.redirectUris -o tsv)
	for HOST in $HOSTS; do
		URIS="https://${HOST}/.auth/login/aad/callback${NL}${URIS}"
	done
	URIS=$(echo "$URIS" | sort | uniq)
	msg "ME-ID App Client ID:    ${MS_CLIENT_ID}"
	msg "ME-ID App Redirect URI: ${URI}"
	msg "Updating new Redirect URIs:${NL}${URIS}"
	confirm
	run az ad app update --id $MS_CLIENT_ID --web-redirect-uris $URIS
}

cmd_meid_secret() {
	HOSTS=$(app_hostnames | grep -v '\*')
	CRED_TIME=$(date +%s)
	CRED_NAME="$HOSTS $CRED_TIME"
	msg "ME-ID App Client ID: ${MS_CLIENT_ID}"
	msg "Adding new Client Secret for $HOSTS"
	confirm
	msg "ME-ID App new credential name: $CRED_NAME"
	PASSWORD=$(az ad app credential reset --id $MS_CLIENT_ID --append --display-name "$CRED_NAME" --end-date 2299-12-31 --query password -o tsv 2>/dev/null)
	run az keyvault secret set --vault-name $AZURE_KEY_VAULT_NAME --name MS-CLIENT-SECRET --file <(echo -n "$PASSWORD") >/dev/null
	run az webapp config appsettings set $AZ_ARGS --settings CRED_NAME="$CRED_NAME"
}

cmd_data_get() {
	if test $# -lt 2; then
		msg 'Specify remote/local paths'
		exit 1
	fi
	run az storage file download --only-show-errors --account-name $AZURE_STORAGE_ACCOUNT_NAME -s data -p "$1" --dest "$2" >/dev/null
}

cmd_data_put() {
	if test $# -lt 2; then
		msg 'Specify remote/local paths'
		exit 1
	fi
	run az storage file upload --only-show-errors --account-name $AZURE_STORAGE_ACCOUNT_NAME -s data -p "$1" --source "$2" >/dev/null
}

cmd_aas_show() {
	run az webapp show $AZ_ARGS
}

cmd_aas_hostnames() {
	ARGS="$AZ_ARGS"
	run az webapp show $ARGS --query hostNames -o tsv
}

cmd_aas_logs() {
	ARGS="$AZ_ARGS"
	run az webapp log tail $ARGS
}

cmd_aas_console() {
	ARGS="$AZ_ARGS"
	run az webapp ssh $ARGS
}

cmd_aas_restart() {
	ARGS="$AZ_ARGS"
	msg "Restarting app..."
	confirm
	run az webapp restart $ARGS
}

cmd_portal_aas() {
	URL="https://portal.azure.com/#@${AZURE_TENANT_ID}/resource/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP_NAME}"
	run xdg-open "$URL"
}

cmd_portal_meid() {
	if test -z "$MS_TENANT_ID" -o -z "$MS_CLIENT_ID"; then
		msg 'Missing MS_TEANT_ID or MS_CLIENT_ID settings'
		exit 1
	fi
	URL="https://portal.azure.com/#@${MS_TENANT_ID}/view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/${MS_CLIENT_ID}"
	run xdg-open "$URL"
}

cmd_open() {
	ARGS="$AZ_ARGS"
	run az webapp browse $ARGS
}

cmd_help() {
	msg "Usage: $0 <command> [options...] [args...]"
	msg "Options":
	msg "  --help,-h                  - Show this help"
	msg "  --no-prompt                - Do not ask for confirmation"
	msg "  --verbose, -v              - Show detailed output"
	msg "  --revision <name>          - Specify revision name"
	msg "  --replica <name>           - Specify replica name"
	msg "  --container <name>         - Specify container name"
	msg "Commands:"
	msg "  meid-redirect              - ME-ID: update app redirect URIs"
	msg "  meid-secret                - ME-ID: create new client secret"
	msg "  data-get <remote> <local>  - Data: download file"
	msg "  data-put <remote> <local>  - Data: upload file"
	msg "  aas-show                   - AAS: show app"
	msg "  aas-hostnames              - AAS: list hostnames"
	msg "  aas-restart                - AAS: restart revision"
	msg "  aas-logs                   - AAS: show container logs"
	msg "  aas-console                - AAS: connect to container"
	msg "  portal-aas                 - Portal: open AAS resource group in browser"
	msg "  portal-meid                - Portal: open ME-ID app registration in browser"
	msg "  open                       - open app in browser"
	exit $1
}

OPTIONS=$(getopt -o hqv -l help -l no-prompt -l verbose -l revision: -l replica: -l container: -- "$@")
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
		-v|--verbose)
			VERBOSE=true
			shift
			;;
		--revision)
			AZ_REVISION=$2
			shift 2
			;;
		--replica)
			AZ_REPLICA=$2
			shift 2
			;;
		--container)
			AZ_CONTAINER=$2
			shift 2
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
	meid-redirect)
		shift
		cmd_meid_redirect "$@"
		;;
	meid-secret)
		shift
		cmd_meid_secret "$@"
		;;
	data-get|download)
		shift
		cmd_data_get "$@"
		;;
	data-put|upload)
		shift
		cmd_data_put "$@"
		;;
	aas-show)
		shift
		cmd_aas_show "$@"
		;;
	aas-hostnames)
		shift
		cmd_aas_hostnames "$@"
		;;
	aas-logs)
		shift
		cmd_aas_logs "$@"
		;;
	aas-console)
		shift
		cmd_aas_console "$@"
		;;
	aas-restart)
		shift
		cmd_aas_restart "$@"
		;;
	portal-aas)
		shift
		cmd_portal_aas "$@"
		;;
	portal-meid)
		shift
		cmd_portal_meid "$@"
		;;
	open)
		shift
		cmd_open "$@"
		;;
	*)
		msg "E: Invalid command: $1"
		cmd_help 1
		;;
esac