#!/bin/bash -xe
#CACHEURL=http://172.22.0.1/images

# Which image should we use
export RHCOS_IMAGE_URL=${1:-$RHCOS_IMAGE_URL}
if [ -z "$RHCOS_IMAGE_URL" ] ; then
    echo "No image URL provided"
    exit 1
fi

# When provided by openshift-installer the URL is like
# "https://releases-art-rhcos.svc.ci.openshift.org/art/storage/releases/rhcos-4.2/420.8.20190708.2/rhcos-420.8.20190708.2-openstack.qcow2"
# In this case we use the URL as-is, otherwise for backwards compatibility
# we figure it out from meta.json (when only the baseURI is provided)
# The latter will be removed when 
# https://github.com/openshift/installer/issues/2064 and
# https://github.com/openshift/installer/issues/2037 are fully completed
if [[ $RHCOS_IMAGE_URL = *.qcow2 ]]; then
    RHCOS_IMAGE_FILENAME_OPENSTACK=$(basename $RHCOS_IMAGE_URL)
    IMAGE_URL=$(dirname $RHCOS_IMAGE_URL)
else
    RHCOS_IMAGE_FILENAME_OPENSTACK="$(curl ${RHCOS_IMAGE_URL}/meta.json | jq -r '.images.openstack.path')"
    IMAGE_URL=${RHCOS_IMAGE_URL}
fi
RHCOS_IMAGE_FILENAME_COMPRESSED=${RHCOS_IMAGE_FILENAME_OPENSTACK/%openstack.qcow2/compressed.qcow2}
FFILENAME="rhcos-ootpa-latest.qcow2"

mkdir -p /shared/html/images /shared/tmp
cd /shared/html/images

if [ -e $FFILENAME.headers ] ; then
    FILECACHED=$(sed -n -e 's/.*filename=\([^\r]\+\).*/\1/p' "$FFILENAME.headers")
    # We already have the required file
    if [ "$FILECACHED" == "${RHCOS_IMAGE_FILENAME_OPENSTACK}" ] ; then
        exit 0
    fi
fi

TMPDIR=$(mktemp -d -p /shared/tmp)
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
    curl --insecure --compressed -L --dump-header "${RHCOS_IMAGE_FILENAME_OPENSTACK}.headers" -o "${RHCOS_IMAGE_FILENAME_OPENSTACK}" "${IMAGE_URL}/${RHCOS_IMAGE_FILENAME_OPENSTACK}"
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

