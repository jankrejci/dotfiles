#!/bin/sh -e
# ESET PROTECT
# Copyright (c) 1992-2025 ESET, spol. s r.o. All Rights Reserved

cleanup_file="$(mktemp -q)"
finalize() {
	set +e
	if test -f "$cleanup_file"; then
		while read f; do
			rm -f "$f"
		done <"$cleanup_file"
		rm -f "$cleanup_file"
	fi
}

trap 'finalize' HUP INT QUIT TERM EXIT

eraa_server_hostname="cahcyuqxf2detlt2vamfjom76y.a.ecaserver.eset.com"
eraa_server_port="443"
eraa_server_company_name='Braiins Systems s.r.o.'
eraa_peer_cert_b64="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"
eraa_peer_cert_pwd=""
eraa_ca_cert_b64="MIIFpDCCA4ygAwIBAgIIMUSW0eFkh/8wDQYJKoZIhvcNAQELBQAwaDELMAkGA1UEBhMCU0sxGDAWBgNVBAgTD1Nsb3ZhayBSZXB1YmxpYzETMBEGA1UEBxMKQnJhdGlzbGF2YTENMAsGA1UEChMERXNldDEbMBkGA1UEAxMSRVBDIEFnZW50IHByb3h5IENBMB4XDTIyMDYyMDAwMDAwMFoXDTMyMDYxOTIzNTk1OVowaDELMAkGA1UEBhMCU0sxGDAWBgNVBAgTD1Nsb3ZhayBSZXB1YmxpYzETMBEGA1UEBxMKQnJhdGlzbGF2YTENMAsGA1UEChMERXNldDEbMBkGA1UEAxMSRVBDIEFnZW50IHByb3h5IENBMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEApFyygZ31hn6s/K7+Lm/r3KP+P5Gn0pb5J6IR0F+KtBUiNE9nRn5PnVDdyj9uVd6BZIKcczoHebH/70GQUuOzprDtHhWUTNDZ7R4NfNz0u5cYn2mKPk9lJRPEcuvqKr+aGsCs1yMv226xd72ngJE/Z2MlGLGX5+kuO0HmQWRUK/SDtmcCvforHs7zE19PjXmZQnpW+bUFkLeHcHS4WtJ64CNkbuTHssK8nNDQoJXLZVKafLWCkAZ94vpZWDRG5AffdBDnKrSy+WOTI6dOJw8i+uJ7YtWconTJo9NRCcgTzCHujylXgqWkwm3f+Wh/h0u5KIJEzTPN/RTzP+/SWEDrYi7+wECXWv6kU3Ty3KkzPGsAt9ABmnvAUGShi8Heyhnes6E3IiUt3wko+LHVw9hFyXFjfqtgRtxvOTcX06zinpQbtl+d1Wm7mU/ORFIPffRec4B9YewF1VRCm4gT5vqFZbO7BUnuyKFeGr6Vxlgrgz0mPS0PAoATI500x9g8Md3Mmshc/6wLInMHgSh//n+aylnePRrTvLEJhcWgoDx57wZ7G5fTeHEFIRrcU3ez6PSKbodCBcjfWrGLkXNQzmIwhDxVRmo4DXLga6MzbYqU54zQVfk60CiFEvwwK8l7WBZ7XlqxRl8QmsIUGf278N8Hxe0qOs7fcZPvuVHyhS4WKxsCAwEAAaNSMFAwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUZ9DJSflsyGkpLas5Ll3dMzeMJSEwCwYDVR0PBAQDAgEGMBEGCWCGSAGG+EIBAQQEAwIABzANBgkqhkiG9w0BAQsFAAOCAgEAWrXSFAd4OmT0bxHj1q+zMROTxXalzfAfqncTGaTm2NiqL5be3WfgnQLjGOMX+VVC1YXDlI2xs2JAWD3myRT4u7g1Y320HmjWczaE36h8PrnL+M/LEIHem3bM7e6ZFGHzwN80D5bmM++qacrGnnSDXid/sVx2Vi5KKXOXcFB74Haef5mqVm9uNpjDuUO+7Zdip6xqieHOpYD7HIWCkq/bJXxyrPr9CY37KyVdeMoU8QuIzdlgn5l0yc8LNBXXv7pba+ykPirIWe1ZR0O0z5e0gAqUe0kz9fpiMmzWpaGS/4s8gt0oYX2Ahibc3Lgg179OOpUFOsz92TmPVQCnzseZCPirikCA7qUAmMFKqs+l+X6DdKIrL4ocHs5zFAL9fysdKpczKczAWpZXr9LtuY6WFDkcWhxm4kj1MXyte8UBBC4C1UX47Km5TlOQUApnp7LMXI3jlBB+2Lo3T9N2FhiQ5R2PoNdA+XONNaBb8E9mh83wOvA6+Me1Rb7bIO6q/dTULd41Jns3JQ8zy0H8rQrOSOREWfieW0Czd38ZRJoa7MRp6Z3aYAuqt8pJpOykVbKQY/OYh43pt5gfgFvIkI3CuoJvLPQ3bYKyBiJN8PYhFpOyLYOrOJqbd26x+QFORgiBdZo6u6Em31l3fVpiaMcSAD9Cny6VUEC2aYn00beB2Vc="
eraa_product_uuid=""
eraa_initial_sg_token="MDAwMDAwMDAtMDAwMC0wMDAwLTcwMDEtMDAwMDAwMDAwMDAxiJxFWqKASBa+zsNTJ2pzDm3WQOS9bk29tKn1ym48Y/HNDVkbsSQE5hoqnC4Ug3jxtNUh9w=="
eraa_policy_data="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"

arch=$(uname -m)
eraa_installer_url="http://repository.eset.com/v1/com/eset/apps/business/era/agent/v12/12.0.1100.0/agent_linux_i386.sh"
eraa_installer_checksum="550682a41a1244314d3a04753ec8de928a22769022b6420d6fd88404c46c0623"

if $(echo "$arch" | grep -E "^(x86_64|amd64)$" 2>&1 >/dev/null); then
	eraa_installer_url="http://repository.eset.com/v1/com/eset/apps/business/era/agent/v12/12.4.1124.0/agent_linux_x86_64.sh"
	eraa_installer_checksum="b87773cd528c65c5d30c45f2fd7bcff18b89787eb95c7436a72e5b39876708a3"
else
	if $(echo "$arch" | grep -E "^(aarch64|arm64)$" 2>&1 >/dev/null); then
		eraa_installer_url=""
		eraa_installer_checksum=""
	fi
fi

echo "ESET Management Agent live installer script. Copyright © 1992-2025 ESET, spol. s r.o. - All rights reserved."

if test ! -z "$eraa_server_company_name"; then
	echo " * CompanyName: $eraa_server_company_name"
fi
echo " * Hostname: $eraa_server_hostname"
echo " * Port: $eraa_server_port"
echo " * Platform: $arch"
echo " * Installer: $eraa_installer_url"
echo

if test -z "$eraa_installer_url"; then
	echo "No installer available for '$arch' arhitecture."
	exit 1
fi

local_cert_path="$(mktemp -q -u)"
echo $eraa_peer_cert_b64 | base64 -d >"$local_cert_path" && echo "$local_cert_path" >>"$cleanup_file"

if test -n "$eraa_ca_cert_b64"; then
	local_ca_path="$(mktemp -q -u)"
	echo $eraa_ca_cert_b64 | base64 -d >"$local_ca_path" && echo "$local_ca_path" >>"$cleanup_file"
fi

eraa_http_proxy_value=""

local_installer="$(dirname $0)"/"$(basename $eraa_installer_url)"

if $(echo "$eraa_installer_checksum  $local_installer" | sha256sum -c 2>/dev/null >/dev/null); then
	echo "Verified local installer was found: '$local_installer'"
else
	local_installer="$(mktemp -q -u)"

	echo "Downloading ESET Management Agent installer..."

	if test -n "$eraa_http_proxy_value"; then
		export use_proxy=yes
		export http_proxy="$eraa_http_proxy_value"
		(wget --connect-timeout 300 --no-check-certificate -O "$local_installer" "$eraa_installer_url" || wget --connect-timeout 300 --no-proxy --no-check-certificate -O "$local_installer" "$eraa_installer_url" || curl --fail --connect-timeout 300 -k "$eraa_installer_url" >"$local_installer") && echo "$local_installer" >>"$cleanup_file"
	else
		(wget --connect-timeout 300 --no-check-certificate -O "$local_installer" "$eraa_installer_url" || curl --fail --connect-timeout 300 -k "$eraa_installer_url" >"$local_installer") && echo "$local_installer" >>"$cleanup_file"
	fi

	if test ! -s "$local_installer"; then
		echo "Failed to download installer file"
		exit 2
	fi

	echo -n "Checking integrity of installer script " && echo "$eraa_installer_checksum  $local_installer" | sha256sum -c
fi

chmod +x "$local_installer"

command -v sudo >/dev/null && usesudo="sudo -E" || usesudo=""

export _ERAAGENT_PEER_CERT_PASSWORD="$eraa_peer_cert_pwd"

echo
echo Running installer script $local_installer

echo "/bin/sh $local_installer \\"
echo "--skip-license \\"
echo "--hostname $eraa_server_hostname \\"
echo "--port $eraa_server_port \\"
echo "--cert-path $local_cert_path \\"
echo "--cert-password env:_ERAAGENT_PEER_CERT_PASSWORD \\"
echo "--cert-password-is-base64 --initial-static-group $eraa_initial_sg_token \\"
echo "\\"
echo "--disable-imp-program \$\(test -n $local_ca_path && echo --cert-auth-path $local_ca_path\) \\"
echo "\$(test -n $eraa_product_uuid && echo --product-guid $eraa_product_uuid) \\"
echo "\$(test -n $eraa_policy_data && echo --custom-policy $eraa_policy_data)"
echo

$usesudo /bin/sh "$local_installer" \
	--skip-license \
	--hostname "$eraa_server_hostname" \
	--port "$eraa_server_port" \
	--cert-path "$local_cert_path" \
	--cert-password "env:_ERAAGENT_PEER_CERT_PASSWORD" \
	--cert-password-is-base64 --initial-static-group "$eraa_initial_sg_token" \
	\
	--disable-imp-program $(test -n "$local_ca_path" && echo --cert-auth-path "$local_ca_path") \
	$(test -n "$eraa_product_uuid" && echo --product-guid "$eraa_product_uuid") \
	$(test -n "$eraa_policy_data" && echo --custom-policy "$eraa_policy_data")
