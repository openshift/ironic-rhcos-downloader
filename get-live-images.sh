#!/bin/bash -xe

# Check and set http(s)_proxy. Required for cURL to use a proxy
export http_proxy=${http_proxy:-$HTTP_PROXY}
export https_proxy=${https_proxy:-$HTTPS_PROXY}
export no_proxy=${no_proxy:-$NO_PROXY}
export CURL_CA_BUNDLE=${CURL_CA_BUNDLE:-/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem}
export IP_OPTIONS=${IP_OPTIONS:-}

# Which image should we use
export RHCOS_IMAGE_URL=${1:-$RHCOS_IMAGE_URL}
if [ -z "$RHCOS_IMAGE_URL" ] ; then
    echo "No image URL provided"
    exit 1
fi

function download_image() {
	CONNECT_TIMEOUT=120
	MAX_ATTEMPTS=5

	for i in $(seq ${MAX_ATTEMPTS}); do
		if ! curl -g --compressed -L --fail --connect-timeout ${CONNECT_TIMEOUT} -o "$1" "$2"; then
			if (( ${i} == ${MAX_ATTEMPTS} )); then
				echo "Download failed."
				exit 1
			else
				SLEEP_TIME=$((i*i))
				echo "Download failed, retrying after ${SLEEP_TIME} seconds..."
				sleep ${SLEEP_TIME}
			fi
		else
			break
		fi
	done
}

function cache_image() {
	FILENAME=$(basename $1)
	FILENAME_CACHED=cached-${FILENAME}
	TMPDIR=$(mktemp -d -p /shared/tmp)
	trap "rm -fr $TMPDIR" EXIT
	cd $TMPDIR

	# We have a file in the cache that matches the one we want, use it
	if [ -s "/shared/html/images/$FILENAME/$FILENAME_CACHED.md5sum" ]; then
		echo "$FILENAME/$FILENAME_CACHED.md5sum found, contents:"
		cat /shared/html/images/$FILENAME/$FILENAME_CACHED.md5sum
	else
		download_image "${FILENAME_CACHED}" "${URL_STRIPPED}"
	fi

	md5sum "$FILENAME_CACHED" | cut -f 1 -d " " > "$FILENAME_CACHED.md5sum"
	cd /shared/html/images
	chmod 755 $TMPDIR
	mv $TMPDIR $FILENAME
	if [[ $FILENAME =~ live-initramfs ]]; then
		ln -sf "$FILENAME/$FILENAME_CACHED" "$FFILENAME.initramfs"
		ln -sf "$FILENAME/$FILENAME_CACHED.md5sum" "$FFILENAME.initramfs.md5sum"
	elif [[ $FILENAME =~ live-rootfs ]]; then
		ln -sf "$FILENAME/$FILENAME_CACHED" "$FFILENAME.rootfs"
		ln -sf "$FILENAME/$FILENAME_CACHED.md5sum" "$FFILENAME.rootfs.md5sum"
	elif [[ $FILENAME =~ live-kernel ]]; then
		ln -sf "$FILENAME/$FILENAME_CACHED" "$FFILENAME.kernel"
		ln -sf "$FILENAME/$FILENAME_CACHED.md5sum" "$FFILENAME.kernel.md5sum"
	elif [[ $FILENAME =~ -live ]] && [[ $FILENAME =~ .iso ]]; then
		ln -sf "$FILENAME/$FILENAME_CACHED" "$FFILENAME.iso"
		ln -sf "$FILENAME/$FILENAME_CACHED.md5sum" "$FFILENAME.iso.md5sum"
		# Append dhcp options for dualstack installs
		if [ -n "$IP_OPTIONS" ] ; then
			coreos-installer iso kargs modify -a "$IP_OPTIONS" "$ISO_FILE"
		fi
		#Recalculate md5sum.
		md5sum "$FILENAME/$FILENAME_CACHED" | cut -f 1 -d " " > "$FILENAME/$FILENAME_CACHED.md5sum"
	fi
}

mkdir -p /shared/html/images /shared/tmp

URLS=($(echo $RHCOS_IMAGE_URL | tr "," "\n"))

# This name will be used in the ironic image to embed the agent ignition
FFILENAME="ironic-python-agent"
for URL in "${URLS[@]}"
do
	URL_STRIPPED=`echo $URL | cut -f 1 -d \?`
	cache_image $URL_STRIPPED
done
