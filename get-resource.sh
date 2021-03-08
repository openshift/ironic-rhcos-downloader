#!/bin/bash -xe

# Check and set http(s)_proxy. Required for cURL to use a proxy
export http_proxy=${http_proxy:-$HTTP_PROXY}
export https_proxy=${https_proxy:-$HTTPS_PROXY}

# Which image should we use
export RHCOS_IMAGE_URL=${1:-$RHCOS_IMAGE_URL}
if [ -z "$RHCOS_IMAGE_URL" ] ; then
    echo "No image URL provided"
    exit 1
fi

# When provided by openshift-installer the URL is like
# "https://releases-art-rhcos.svc.ci.openshift.org/art/storage/releases/rhcos-4.2/420.8.20190708.2/rhcos-420.8.20190708.2-openstack.qcow2.gz?sha256=xxx"
# NOTE: strip sha256 query string in the image url
RHCOS_IMAGE_URL_STRIPPED=`echo $RHCOS_IMAGE_URL | cut -f 1 -d \?`
if [[ $RHCOS_IMAGE_URL_STRIPPED =~ qcow2(\.[gx]z)?$ ]]; then
    RHCOS_IMAGE_FILENAME_RAW=$(basename $RHCOS_IMAGE_URL_STRIPPED)
    RHCOS_IMAGE_FILENAME_QCOW=${RHCOS_IMAGE_FILENAME_RAW/%.[gx]z}
    IMAGE_FILENAME_EXTENSION=${RHCOS_IMAGE_FILENAME_RAW/$RHCOS_IMAGE_FILENAME_QCOW}
    IMAGE_URL=$(dirname $RHCOS_IMAGE_URL_STRIPPED)
else
    echo "Unexpected image format $RHCOS_IMAGE_URL"
    exit 1
fi

RHCOS_IMAGE_FILENAME_CACHED=cached-${RHCOS_IMAGE_FILENAME_QCOW}
FFILENAME="rhcos-ootpa-latest.qcow2"

mkdir -p /shared/html/images /shared/tmp
TMPDIR=$(mktemp -d -p /shared/tmp)
cd $TMPDIR

# We have a file in the cache that matches the one we want, use it
if [ -s "/shared/html/images/$RHCOS_IMAGE_FILENAME_QCOW/$RHCOS_IMAGE_FILENAME_CACHED.md5sum" ]; then
    echo "$RHCOS_IMAGE_FILENAME_QCOW/$RHCOS_IMAGE_FILENAME_CACHED.md5sum found, contents:"
    cat /shared/html/images/$RHCOS_IMAGE_FILENAME_QCOW/$RHCOS_IMAGE_FILENAME_CACHED.md5sum
else
    CONNECT_TIMEOUT=120
    MAX_ATTEMPTS=5

    for i in $(seq ${MAX_ATTEMPTS}); do
        if ! curl -g --insecure --compressed -L --connect-timeout ${CONNECT_TIMEOUT} -o "${RHCOS_IMAGE_FILENAME_RAW}" "${IMAGE_URL}/${RHCOS_IMAGE_FILENAME_RAW}"; then
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

    if [[ $IMAGE_FILENAME_EXTENSION == .gz ]]; then
      gzip -d "$RHCOS_IMAGE_FILENAME_RAW"
    elif [[ $IMAGE_FILENAME_EXTENSION == .xz ]]; then
      unxz "$RHCOS_IMAGE_FILENAME_RAW"
    fi

    qemu-img convert -O qcow2 -c "$RHCOS_IMAGE_FILENAME_QCOW" "$RHCOS_IMAGE_FILENAME_CACHED"
    md5sum "$RHCOS_IMAGE_FILENAME_CACHED" | cut -f 1 -d " " > "$RHCOS_IMAGE_FILENAME_CACHED.md5sum"
fi

if [ -s "${RHCOS_IMAGE_FILENAME_CACHED}.md5sum" ] ; then
    cd /shared/html/images
    chmod 755 $TMPDIR
    mv $TMPDIR $RHCOS_IMAGE_FILENAME_QCOW
    ln -sf "$RHCOS_IMAGE_FILENAME_QCOW/$RHCOS_IMAGE_FILENAME_CACHED" $FFILENAME
    ln -sf "$RHCOS_IMAGE_FILENAME_QCOW/$RHCOS_IMAGE_FILENAME_CACHED.md5sum" "$FFILENAME.md5sum"
else
    rm -rf $TMPDIR
fi

# For backwards compatibility, if the rhcos image name contains -openstack, we want to
# create a symlink to the original in the old format.  The old format had a substitution
# which required the existence of -openstack in the name.
if [[ ${RHCOS_IMAGE_FILENAME_QCOW} == *"-openstack"* ]] ; then
    cd "/shared/html/images/${RHCOS_IMAGE_FILENAME_QCOW}"
    RHCOS_IMAGE_FILENAME_COMPRESSED=${RHCOS_IMAGE_FILENAME_QCOW/-openstack/-compressed}
    ln -sf "$RHCOS_IMAGE_FILENAME_CACHED" "$RHCOS_IMAGE_FILENAME_COMPRESSED"
    ln -sf "$RHCOS_IMAGE_FILENAME_CACHED.md5sum" "$RHCOS_IMAGE_FILENAME_COMPRESSED.md5sum"
fi

