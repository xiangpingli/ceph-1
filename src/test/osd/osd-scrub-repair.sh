#!/bin/bash
#
# Copyright (C) 2014 Red Hat <contact@redhat.com>
#
# Author: Loic Dachary <loic@dachary.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU Library Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Library Public License for more details.
#
source $(dirname $0)/../detect-build-env-vars.sh
source $CEPH_ROOT/qa/workunits/ceph-helpers.sh

function run() {
    local dir=$1
    shift

    export CEPH_MON="127.0.0.1:7107" # git grep '\<7107\>' : there must be only one
    export CEPH_ARGS
    CEPH_ARGS+="--fsid=$(uuidgen) --auth-supported=none "
    CEPH_ARGS+="--mon-host=$CEPH_MON "

    local funcs=${@:-$(set | sed -n -e 's/^\(TEST_[0-9a-z_]*\) .*/\1/p')}
    for func in $funcs ; do
        $func $dir || return 1
    done
}

function add_something() {
    local dir=$1
    local poolname=$2
    local obj=${3:-SOMETHING}

    wait_for_clean || return 1

    ceph osd set noscrub || return 1
    ceph osd set nodeep-scrub || return 1

    local payload=ABCDEF
    echo $payload > $dir/ORIGINAL
    rados --pool $poolname put $obj $dir/ORIGINAL || return 1
    # Ignore errors for EC pools
    rados --pool $poolname setomapheader $obj hdr-$obj || true
    rados --pool $poolname setomapval $obj key-$obj val-$obj || true
}

#
# Corrupt one copy of a replicated pool
#
function TEST_corrupt_and_repair_replicated() {
    local dir=$1
    local poolname=rbd

    setup $dir || return 1
    run_mon $dir a --osd_pool_default_size=2 || return 1
    run_osd $dir 0 || return 1
    run_osd $dir 1 || return 1

    add_something $dir $poolname
    corrupt_and_repair_one $dir $poolname $(get_not_primary $poolname SOMETHING) || return 1
    # Reproduces http://tracker.ceph.com/issues/8914
    corrupt_and_repair_one $dir $poolname $(get_primary $poolname SOMETHING) || return 1

    teardown $dir || return 1
}

function corrupt_and_repair_two() {
    local dir=$1
    local poolname=$2
    local first=$3
    local second=$4

    #
    # 1) remove the corresponding file from the OSDs
    #
    pids=""
    run_in_background pids objectstore_tool $dir $first SOMETHING remove
    run_in_background pids objectstore_tool $dir $second SOMETHING remove
    wait_background pids
    return_code=$?
    if [ $return_code -ne 0 ]; then return $return_code; fi

    #
    # 2) repair the PG
    #
    local pg=$(get_pg $poolname SOMETHING)
    repair $pg
    #
    # 3) The files must be back
    #
    pids=""
    run_in_background pids objectstore_tool $dir $first SOMETHING list-attrs
    run_in_background pids objectstore_tool $dir $second SOMETHING list-attrs
    wait_background pids
    return_code=$?
    if [ $return_code -ne 0 ]; then return $return_code; fi

    rados --pool $poolname get SOMETHING $dir/COPY || return 1
    diff $dir/ORIGINAL $dir/COPY || return 1
}

#
# 1) add an object
# 2) remove the corresponding file from a designated OSD
# 3) repair the PG
# 4) check that the file has been restored in the designated OSD
#
function corrupt_and_repair_one() {
    local dir=$1
    local poolname=$2
    local osd=$3

    #
    # 1) remove the corresponding file from the OSD
    #
    objectstore_tool $dir $osd SOMETHING remove || return 1
    #
    # 2) repair the PG
    #
    local pg=$(get_pg $poolname SOMETHING)
    repair $pg
    #
    # 3) The file must be back
    #
    objectstore_tool $dir $osd SOMETHING list-attrs || return 1
    rados --pool $poolname get SOMETHING $dir/COPY || return 1
    diff $dir/ORIGINAL $dir/COPY || return 1

    wait_for_clean || return 1
}

function corrupt_and_repair_erasure_coded() {
    local dir=$1
    local poolname=$2
    local profile=$3

    ceph osd pool create $poolname 1 1 erasure $profile \
        || return 1

    add_something $dir $poolname

    local primary=$(get_primary $poolname SOMETHING)
    local -a osds=($(get_osds $poolname SOMETHING | sed -e "s/$primary//"))
    local not_primary_first=${osds[0]}
    local not_primary_second=${osds[1]}

    # Reproduces http://tracker.ceph.com/issues/10017
    corrupt_and_repair_one $dir $poolname $primary  || return 1
    # Reproduces http://tracker.ceph.com/issues/10409
    corrupt_and_repair_one $dir $poolname $not_primary_first || return 1
    corrupt_and_repair_two $dir $poolname $not_primary_first $not_primary_second || return 1
    corrupt_and_repair_two $dir $poolname $primary $not_primary_first || return 1

}

function TEST_auto_repair_erasure_coded() {
    local dir=$1
    local poolname=ecpool

    # Launch a cluster with 5 seconds scrub interval
    setup $dir || return 1
    run_mon $dir a || return 1
    for id in $(seq 0 2) ; do
        run_osd $dir $id \
            --osd-scrub-auto-repair=true \
            --osd-deep-scrub-interval=5 \
            --osd-scrub-max-interval=5 \
            --osd-scrub-min-interval=5 \
            --osd-scrub-interval-randomize-ratio=0
    done

    # Create an EC pool
    ceph osd erasure-code-profile set myprofile \
        k=2 m=1 ruleset-failure-domain=osd || return 1
    ceph osd pool create $poolname 8 8 erasure myprofile || return 1

    # Put an object
    local payload=ABCDEF
    echo $payload > $dir/ORIGINAL
    rados --pool $poolname put SOMETHING $dir/ORIGINAL || return 1
    wait_for_clean || return 1

    # Remove the object from one shard physically
    objectstore_tool $dir $(get_not_primary $poolname SOMETHING) SOMETHING remove || return 1
    # Wait for auto repair
    local pgid=$(get_pg $poolname SOMETHING)
    wait_for_scrub $pgid "$(get_last_scrub_stamp $pgid)"
    wait_for_clean || return 1
    # Verify - the file should be back
    objectstore_tool $dir $(get_not_primary $poolname SOMETHING) SOMETHING list-attrs || return 1
    rados --pool $poolname get SOMETHING $dir/COPY || return 1
    diff $dir/ORIGINAL $dir/COPY || return 1

    # Tear down
    teardown $dir || return 1
}

function TEST_corrupt_and_repair_jerasure() {
    local dir=$1
    local poolname=ecpool
    local profile=myprofile

    setup $dir || return 1
    run_mon $dir a || return 1
    for id in $(seq 0 3) ; do
        run_osd $dir $id || return 1
    done
    wait_for_clean || return 1

    ceph osd erasure-code-profile set $profile \
        k=2 m=2 ruleset-failure-domain=osd || return 1

    corrupt_and_repair_erasure_coded $dir $poolname $profile || return 1

    teardown $dir || return 1
}

function TEST_corrupt_and_repair_lrc() {
    local dir=$1
    local poolname=ecpool
    local profile=myprofile

    setup $dir || return 1
    run_mon $dir a || return 1
    for id in $(seq 0 9) ; do
        run_osd $dir $id || return 1
    done
    wait_for_clean || return 1

    ceph osd erasure-code-profile set $profile \
        pluing=lrc \
        k=4 m=2 l=3 \
        ruleset-failure-domain=osd || return 1

    corrupt_and_repair_erasure_coded $dir $poolname $profile || return 1

    teardown $dir || return 1
}

function TEST_unfound_erasure_coded() {
    local dir=$1
    local poolname=ecpool
    local payload=ABCDEF

    setup $dir || return 1
    run_mon $dir a || return 1
    run_osd $dir 0 || return 1
    run_osd $dir 1 || return 1
    run_osd $dir 2 || return 1
    run_osd $dir 3 || return 1
    wait_for_clean || return 1

    ceph osd erasure-code-profile set myprofile \
      k=2 m=2 ruleset-failure-domain=osd || return 1
    ceph osd pool create $poolname 1 1 erasure myprofile \
      || return 1

    add_something $dir $poolname

    local primary=$(get_primary $poolname SOMETHING)
    local -a osds=($(get_osds $poolname SOMETHING | sed -e "s/$primary//"))
    local not_primary_first=${osds[0]}
    local not_primary_second=${osds[1]}
    local not_primary_third=${osds[2]}

    #
    # 1) remove the corresponding file from the OSDs
    #
    pids=""
    run_in_background pids objectstore_tool $dir $not_primary_first SOMETHING remove
    run_in_background pids objectstore_tool $dir $not_primary_second SOMETHING remove
    run_in_background pids objectstore_tool $dir $not_primary_third SOMETHING remove
    wait_background pids
    return_code=$?
    if [ $return_code -ne 0 ]; then return $return_code; fi

    #
    # 2) repair the PG
    #
    local pg=$(get_pg $poolname SOMETHING)
    repair $pg
    #
    # 3) check pg state
    #
    ceph -s|grep "4 osds: 4 up, 4 in" || return 1
    ceph -s|grep "1/1 unfound" || return 1

    teardown $dir || return 1
}

#
# list_missing for EC pool
#
function TEST_list_missing_erasure_coded() {
    local dir=$1
    local poolname=ecpool
    local profile=myprofile

    setup $dir || return 1
    run_mon $dir a || return 1
    for id in $(seq 0 2) ; do
        run_osd $dir $id || return 1
    done
    wait_for_clean || return 1

    ceph osd erasure-code-profile set $profile \
        k=2 m=1 ruleset-failure-domain=osd || return 1
    ceph osd pool create $poolname 1 1 erasure $profile \
        || return 1
    wait_for_clean || return 1

    # Put an object and remove the two shards (including primary)
    add_something $dir $poolname OBJ0 || return 1
    local -a osds0=($(get_osds $poolname OBJ0))

    # Put another object and remove two shards (excluding primary)
    add_something $dir $poolname OBJ1 || return 1
    local -a osds1=($(get_osds $poolname OBJ1))

    # Stop all osd daemons
    for id in $(seq 0 2) ; do
        kill_daemons $dir TERM osd.$id >&2 < /dev/null || return 1
    done

    id=${osds0[0]}
    ceph-objectstore-tool --data-path $dir/$id --journal-path $dir/$id/journal \
        OBJ0 remove || return 1
    id=${osds0[1]}
    ceph-objectstore-tool --data-path $dir/$id --journal-path $dir/$id/journal \
        OBJ0 remove || return 1

    id=${osds1[1]}
    ceph-objectstore-tool --data-path $dir/$id --journal-path $dir/$id/journal \
        OBJ1 remove || return 1
    id=${osds1[2]}
    ceph-objectstore-tool --data-path $dir/$id --journal-path $dir/$id/journal \
        OBJ1 remove || return 1

    for id in $(seq 0 2) ; do
        activate_osd $dir $id >&2 || return 1
    done
    wait_for_clean >&2

    # Get get - both objects should in the same PG
    local pg=$(get_pg $poolname OBJ0)

    # Repair the PG, which triggers the recovering,
    # and should mark the object as unfound
    ceph pg repair $pg
    
    for i in $(seq 0 120) ; do
        [ $i -lt 60 ] || return 1
        matches=$(ceph pg $pg list_missing | egrep "OBJ0|OBJ1" | wc -l)
        [ $matches -eq 2 ] && break
    done

    teardown $dir || return 1
}

#
# Corrupt one copy of a replicated pool
#
function TEST_corrupt_scrub_replicated() {
    local dir=$1
    local poolname=csr_pool
    local total_objs=7

    setup $dir || return 1
    run_mon $dir a --osd_pool_default_size=2 || return 1
    run_osd $dir 0 || return 1
    run_osd $dir 1 || return 1
    wait_for_clean || return 1

    ceph osd pool create $poolname 1 1 || return 1
    wait_for_clean || return 1

    local scrub_only=0
    for i in $(seq 1 $total_objs) ; do
        objname=OBJ${i}
        add_something $dir $poolname $objname

        case $i in
        1)
            # Size (deep scrub data_digest too)
            local payload=UVWXYZZZ
            echo $payload > $dir/CORRUPT
            objectstore_tool $dir $(expr $i % 2) $objname set-bytes $dir/CORRUPT || return 1
            scrub_only=$(expr $scrub_only + 1)
            ;;

        2)
            # digest (deep scrub only)
            local payload=UVWXYZ
            echo $payload > $dir/CORRUPT
            objectstore_tool $dir $(expr $i % 2) $objname set-bytes $dir/CORRUPT || return 1
            ;;

        3)
             # missing
             objectstore_tool $dir $(expr $i % 2) $objname remove || return 1
             scrub_only=$(expr $scrub_only + 1)
             ;;

         4)
             # Modify omap value (deep scrub only)
             objectstore_tool $dir $(expr $i % 2) $objname set-omap key-$objname $dir/CORRUPT || return 1
             ;;

         5)
            # Delete omap key (deep scrub only)
            objectstore_tool $dir $(expr $i % 2) $objname rm-omap key-$objname || return 1
            ;;

         6)
            # Add extra omap key (deep scrub only)
            echo extra > $dir/extra-val
            objectstore_tool $dir $(expr $i % 2) $objname set-omap key2-$objname $dir/extra-val || return 1
            rm $dir/extra-val
            ;;
         7)
            # Modify omap header (deep scrub only)
            echo newheader > $dir/hdr
            objectstore_tool $dir $(expr $i % 2) $objname set-omaphdr $dir/hdr || return 1
            rm $dir/hdr
            ;;
        esac
    done

    local pg=$(get_pg $poolname OBJ0)
    pg_scrub $pg

    rados list-inconsistent-pg $poolname > $dir/json || return 1
    # Check pg count
    test $(jq '. | length' $dir/json) = "1" || return 1
    # Check pgid
    test $(jq -r '.[0]' $dir/json) = $pg || return 1

    rados list-inconsistent-obj $pg > $dir/json || return 1
    # Get epoch for repair-get requests
    epoch=$(jq .epoch $dir/json)
    # Check object count
    test $(jq '.inconsistents | length' $dir/json) = "$scrub_only" || return 1

    jq '.inconsistents | sort' > $dir/checkcsjson << EOF
{"epoch":54,"inconsistents":[{"object":{"name":"OBJ1","nspace":"","locator":"",
"snap":"head"},"errors":["size_mismatch"],"shards":[{"osd":0,"size":7,
"errors":[]},{"osd":1,"size":9,"errors":["size_mismatch"]}]},{"object":
{"name":"OBJ3","nspace":"","locator":"","snap":"head"},"errors":["missing"],
"shards":[{"osd":0,"size":7,"errors":[]},{"osd":1,"errors":["missing"]}]}]}
EOF

    jq '.inconsistents | sort' $dir/json > $dir/csjson
    diff -y $dir/checkcsjson $dir/csjson || return 1

    pg_deep_scrub $pg

    rados list-inconsistent-pg $poolname > $dir/json || return 1
    # Check pg count
    test $(jq '. | length' $dir/json) = "1" || return 1
    # Check pgid
    test $(jq -r '.[0]' $dir/json) = $pg || return 1

    rados list-inconsistent-obj $pg > $dir/json || return 1
    # Get epoch for repair-get requests
    epoch=$(jq .epoch $dir/json)
    # Check object count
    test $(jq '.inconsistents | length' $dir/json) = "$total_objs" || return 1

    jq '.inconsistents | sort' > $dir/checkcsjson << EOF
{"epoch":61,"inconsistents":[{"object":{"name":"OBJ1","nspace":"","locator":"",
"snap":"head"},"errors":["data_digest_mismatch","size_mismatch"],"shards":
[{"osd":0,"size":7,"omap_digest":"0xef54f3bc","data_digest":"0x2ddbf8f5",
"errors":[]},{"osd":1,"size":9,"omap_digest":"0xef54f3bc","data_digest":
"0x2d4a11c2","errors":["data_digest_mismatch","size_mismatch"]}]},{"object":
{"name":"OBJ2","nspace":"","locator":"","snap":"head"},"errors":
["data_digest_mismatch"],"shards":[{"osd":0,"size":7,"omap_digest":"0xdf2f1440",
"data_digest":"0x578a4830","errors":["data_digest_mismatch"]},{"osd":1,"size":7,
"omap_digest":"0xdf2f1440","data_digest":"0x2ddbf8f5","errors":[]}]},{"object":
{"name":"OBJ3","nspace":"","locator":"","snap":"head"},"errors":["missing"],
"shards":[{"osd":0,"size":7,"omap_digest":"0x33a264bb","data_digest":
"0x2ddbf8f5","errors":[]},{"osd":1,"errors":["missing"]}]},{"object":{"name":
"OBJ4","nspace":"","locator":"","snap":"head"},"errors":
["omap_digest_mismatch"],"shards":[{"osd":0,"size":7,"omap_digest":"0x98c0d4b9",
"data_digest":"0x2ddbf8f5","errors":[]},{"osd":1,"size":7,"omap_digest":
"0xbfd8dbb8","data_digest":"0x2ddbf8f5","errors":[]}]},{"object":{"name":"OBJ5",
"nspace":"","locator":"","snap":"head"},"errors":["omap_digest_mismatch"],
"shards":[{"osd":0,"size":7,"omap_digest":"0x5355ab43","data_digest":
"0x2ddbf8f5","errors":[]},{"osd":1,"size":7,"omap_digest":"0xdeb72ab3",
"data_digest":"0x2ddbf8f5","errors":[]}]},{"object":{"name":"OBJ6","nspace":"",
"locator":"","snap":"head"},"errors":["omap_digest_mismatch"],"shards":[{"osd":
0,"size":7,"omap_digest":"0xd986f688","data_digest":"0x2ddbf8f5","errors":[]},
{"osd":1,"size":7,"omap_digest":"0x632e4cbf","data_digest":"0x2ddbf8f5",
"errors":[]}]},{"object":{"name":"OBJ7","nspace":"","locator":"","snap":"head"},
"errors":["omap_digest_mismatch"],"shards":[{"osd":0,"size":7,"omap_digest":
"0x8fa33c44","data_digest":"0x2ddbf8f5","errors":[]},{"osd":1,"size":7,
"omap_digest":"0x1d000c1b","data_digest":"0x2ddbf8f5","errors":[]}]}]}
EOF

    jq '.inconsistents | sort' $dir/json > $dir/csjson
    diff -y $dir/checkcsjson $dir/csjson || return 1

    rados rmpool $poolname $poolname --yes-i-really-really-mean-it
    teardown $dir || return 1
}


main osd-scrub-repair "$@"

# Local Variables:
# compile-command: "cd ../.. ; make -j4 && \
#    test/osd/osd-scrub-repair.sh # TEST_corrupt_and_repair_replicated"
# End:
