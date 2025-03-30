#!/bin/bash

set -e

: ${NOPROMPT=false}
: ${VERBOSE=false}

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

cmd_rclone_config() {
	if test -z "$NGINX_SITE_SAS_URL"; then
		eval $(run azd env get-values)
		msg "Running: az storage share generate-sas"
		EXPIRY=$(date -u -d '10 minutes' '+%Y-%m-%dT%H:%MZ')
		SAS=$(az storage share generate-sas --only-show-errors --account-name $AZURE_STORAGE_ACCOUNT_NAME --name nginx --permissions rcwdl --expiry $EXPIRY --https-only --output tsv)
		NGINX_SITE_SAS_URL="https://${AZURE_STORAGE_ACCOUNT_NAME}.file.core.windows.net/nginx?$SAS"
	fi
	msg "Running: rclone config"
	rclone config create remote azurefiles sas_url "$NGINX_SITE_SAS_URL" >/dev/null
}

cmd_rclone_sync() {
	SITE_NAME=${1-default}
	msg "Syncing to remote site: $SITE_NAME"
	run rclone sync --verbose site/. remote:data/sites/$SITE_NAME/.
	run rclone sync --verbose templates/. remote:templates/.
}

cmd_help() {
	msg "Usage: $0 <command> [options...] [args...]"
	msg "Options":
	msg "  --help,-h                  - Show this help"
	msg "  --no-prompt                - Do not ask for confirmation"
	msg "  --verbose, -v              - Show detailed output"
	msg "Commands:"
	msg "  rclone-config              - Rclone: config"
	msg "  rclone-sync [site_name]    - Rclone: sync"
	exit $1
}

OPTIONS=$(getopt -o hqv -l help -l no-prompt -l verbose -- "$@")
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
	rclone-config)
		shift
		cmd_rclone_config "$@"
		;;
	rclone-sync)
		shift
		cmd_rclone_sync "$@"
		;;
	*)
		msg "E: Invalid command: $1"
		cmd_help 1
		;;
esac