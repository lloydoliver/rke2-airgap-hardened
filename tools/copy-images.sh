#!/bin/sh

IMAGELIST=${1:-rancher-images.txt}

SRC_REPO=${2:-"docker.io"}
DEST_REPO=${3:-"harbor.brynnharrison.com/myrancher"}

IMAGE_COUNT=`wc -l $IMAGELIST | awk '{print $1}'`
COUNT=1




for IMAGE in `cat $IMAGELIST`; do
    echo ""
    echo "-- $IMAGE $COUNT/$IMAGE_COUNT"
    echo ""
    echo "   Checking for $IMAGE on $DEST_REPO"
    

    case $IMAGE in
    */*)
        SRC=docker://${SRC_REPO}/${IMAGE} 
        DEST=docker://${DEST_REPO}/${IMAGE}
        ;;
    *)
        SRC=docker://${SRC_REPO}/library/${IMAGE}
        DEST=docker://${DEST_REPO}/${IMAGE}
        ;;
    esac
    
    DOWNLOAD=0

    SRC_MANIFEST=`skopeo inspect --raw $SRC`
    SRC_MANIFEST_LINUX=`echo $SRC_MANIFEST | grep linux`
    SRC_MANIFEST_WINDOWS=`echo $SRC_MANIFEST | grep windows`
    

    skopeo inspect --raw $DEST &>/dev/null
    RETURN_CODE=$?

    if [[ $RETURN_CODE == 0 ]]; then
        DEST_MANIFEST=`skopeo inspect --raw $DEST`
        DEST_MANIFEST_LINUX=`echo $DEST_MANIFEST | grep linux`
        DEST_MANIFEST_WINDOWS=`echo $DEST_MANIFEST | grep windows`

        if [[ $SRC_MANIFEST_WINDOWS != "" ]]; then
            if [[ $DEST_MANIFEST_LINUX == "" || $DEST_MANIFEST_WINDOWS == "" ]]; then
                skopeo delete $DEST
                DOWNLOAD=1
                OS="--all"
            else
                DOWNLOAD=0
            fi
        fi
    else
        DOWNLOAD=1
    fi
 
    if [[ $DOWNLOAD == 1 ]]; then
        echo "   Copy $IMAGE"
        echo ""
        echo "============================================="

        RETRY=0
        READY=0
        while [[ $READY == 0 ]];
        do
            skopeo copy $OS --src-no-creds --dest-creds $HARBOR_USERNAME:$HARBOR_PASSWORD $SRC $DEST
            RETURN_CODE=$?
            if [[ $RETURN_CODE != 1 || $RETRY > 3 ]]; then
                READY=1
            else
                echo "============================================="
                echo "   Retry downloading $IMAGE $RETRY/5"
                let RETRY++
                sleep 1
            fi
        done

        echo "============================================="
    else
        echo "   Image $IMAGE found"
    fi
    let COUNT++
done