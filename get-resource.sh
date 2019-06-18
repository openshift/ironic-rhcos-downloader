#!/bin/bash -xe
#CACHEURL=http://172.22.0.1/images

# Which image should we use
export RHCOS_IMAGE_URL=${1:-}
if [ -z "$RHCOS_IMAGE_URL" ] ; then
    echo "No image URL provided"
    exit 1
fi

RHCOS_IMAGE_FILENAME_OPENSTACK_GZ="$(curl ${RHCOS_IMAGE_URL}/meta.json | jq -r '.images.openstack.path')"
RHCOS_IMAGE_NAME=$(echo $RHCOS_IMAGE_FILENAME_OPENSTACK_GZ | sed -e 's/-openstack.*//')
RHCOS_IMAGE_FILENAME_OPENSTACK="${RHCOS_IMAGE_NAME}-openstack.qcow2"
RHCOS_IMAGE_FILENAME_COMPRESSED="${RHCOS_IMAGE_NAME}-compressed.qcow2"
FFILENAME="rhcos-ootpa-latest.qcow2"

mkdir -p /shared/html/images
cd /shared/html/images

if [ -e $FFILENAME.headers ] ; then
    FILECACHED=$(sed -n -e 's/.*filename=\([^\r]\+\).*/\1/p' "$FFILENAME.headers")
    # We already have the required file
    if [ "$FILECACHED" == "${RHCOS_IMAGE_FILENAME_OPENSTACK}" ] ; then
        exit 0
    fi
fi

TMPDIR=$(mktemp -d)
cd $TMPDIR

# If we have a CACHEURL, download the headers file for the image its using
# if it matches the filename we want then we are going to use it
if [ -n "$CACHEURL" ] && curl --fail -O "$CACHEURL/$FFILENAME.headers" ; then
    FILECACHED=$(sed -n -e 's/.*filename=\([^\r]\+\).*/\1/p' "$FFILENAME.headers")
fi

# We have a File in the cache that matches the one we want, use it
if [ "$FILECACHED" == "${RHCOS_IMAGE_FILENAME_OPENSTACK}" ] ; then
    mv $FFILENAME.headers "${RHCOS_IMAGE_FILENAME_OPENSTACK}.headers"
    curl -O "$CACHEURL/$RHCOS_IMAGE_FILENAME_OPENSTACK/$RHCOS_IMAGE_FILENAME_COMPRESSED"
    curl -O "$CACHEURL/$RHCOS_IMAGE_FILENAME_OPENSTACK/$RHCOS_IMAGE_FILENAME_OPENSTACK"
    curl -O "$CACHEURL/$RHCOS_IMAGE_FILENAME_OPENSTACK/$RHCOS_IMAGE_FILENAME_COMPRESSED.md5sum"
else
    curl --insecure --compressed -L --dump-header "${RHCOS_IMAGE_FILENAME_OPENSTACK}.headers" -o "${RHCOS_IMAGE_FILENAME_OPENSTACK}" "${RHCOS_IMAGE_URL}/${RHCOS_IMAGE_FILENAME_OPENSTACK}"
    qemu-img convert -O qcow2 -c "$RHCOS_IMAGE_FILENAME_OPENSTACK" "$RHCOS_IMAGE_FILENAME_COMPRESSED"
    md5sum "$RHCOS_IMAGE_FILENAME_COMPRESSED" | cut -f 1 -d " " > "$RHCOS_IMAGE_FILENAME_COMPRESSED.md5sum"
fi

if [ -s "${RHCOS_IMAGE_FILENAME_OPENSTACK}" ] ; then
    cd -
    chmod 755 $TMPDIR
    mv $TMPDIR $RHCOS_IMAGE_FILENAME_OPENSTACK
    ln -sf "$RHCOS_IMAGE_FILENAME_OPENSTACK/$RHCOS_IMAGE_FILENAME_OPENSTACK.headers" $FFILENAME.headers
    ln -sf "$RHCOS_IMAGE_FILENAME_OPENSTACK/$RHCOS_IMAGE_FILENAME_COMPRESSED" $FFILENAME
    ln -sf "$RHCOS_IMAGE_FILENAME_OPENSTACK/$RHCOS_IMAGE_FILENAME_COMPRESSED.md5sum" "$FFILENAME.md5sum"
else
    rm -rf $TMPDIR
fi
