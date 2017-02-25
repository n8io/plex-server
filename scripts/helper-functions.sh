#!/bin/bash
set -e

DEF_CTL_BIN="which encfsctl"
DEF_ENC_DIR_LOCAL="$([ ! -z "$ENC_DIR_LOCAL" ] && echo "$ENC_DIR_LOCAL" || echo "/mnt/x/encrypted")"
DEF_ENCFS6_CONFIG="$([ ! -z "$ENCFS6_CONFIG" ] && echo "$ENCFS6_CONFIG" || echo "/encfs.xml")"

export \
  ENCFS_CTL_BIN="${1:-$DEF_CTL_BIN}" \
  ENCFS6_CONFIG="${2:-$DEF_ENCFS6_CONFIG}" \
  ENC_DIR_LOCAL="${3:-$DEF_ENC_DIR_LOCAL}" \
  ;

decode() {
  ENCFS6_CONFIG="$ENCFS6_CONFIG" "$ENCFS_CTL_BIN" decode . "${1:?A path to decode is required}" || return 1
}

encode() {
  ENCFS6_CONFIG="$ENCFS6_CONFIG" "$ENCFS_CTL_BIN" encode . "${1:?A path to encode is required}" || return 1
}
