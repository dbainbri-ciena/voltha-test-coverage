#!/usr/bin/env bash

# Gerrit branch diff-er

set -eu -o pipefail

UPDATE_GIT=${UPDATE_GIT:-no}
SUBJECT_LEN=${SUBJECT_LEN:-40}
VERIFIED=${VERIFIED:-yes}

if [ "$VERIFIED" == "yes" ]; then
    VOPT="label:verified+"
else
    VOPT=""
fi

REPOS="voltha-bbsim \
    voltha-go \
    voltha-openolt-adapter \
    voltha-openonu-adapter \
    pyvoltha"

REPOS="voltha-adtran-adapter \
    voltha-api-server \
    voltha-bal \
    voltha-bbsim \
    bbsim \
    voltha-docs \
    voltha-go \
    voltha-helm-charts \
    voltha-omci \
    voltha-onos \
    voltha-openolt-adapter \
    voltha-openonu-adapter \
    voltha-protos \
    voltha-simolt-adapter \
    voltha-simonu-adapter \
    voltha-system-tests \
    pyvoltha"

REPOS="voltctl \
    voltha-api-server \
    voltha-lib-go \
    voltha-go \
    voltha-openolt-adapter \
    voltha-simolt-adapter \
    voltha-simonu-adapter \
    -voltha-openonu-adapter \
    -pyvoltha"

FORMAT="%s|%s|%s\n"

bold=$(tput bold)
normal=$(tput sgr0)

if [ "$UPDATE_GIT" == "yes" ]; then
    for REPO in $REPOS; do
        REPO_OPT=${REPO:0:1}
        if [ "$REPO_OPT" == "-" ]; then
            REPO=${REPO:1}
        fi
        if [ ! -d $REPO ]; then
            git clone http://gerrit.opencord.org/$REPO
        else
            cd $REPO
            git fetch --all
            git reset --hard origin/master
            cd ..
        fi
    done
fi

howlong() {
    local TODAY=$(date -u +%Y-%m-%d)
    local WHEN=$(echo $1 | awk '{print $1}')

    local T_Y=$(echo $TODAY | cut -d- -f1)
    local T_M=$(echo $TODAY | cut -d- -f2 | sed -e 's/^0//g')
    local T_D=$(echo $TODAY | cut -d- -f3 | sed -e 's/^0//g')

    local W_Y=$(echo $WHEN | cut -d- -f1)
    local W_M=$(echo $WHEN | cut -d- -f2 | sed -e 's/^0//g')
    local W_D=$(echo $WHEN | cut -d- -f3 | sed -e 's/^0//g')

    python -c "from datetime import date; print (date($T_Y,$T_M,$T_D)-date($W_Y,$W_M,$W_D)).days"
}

TAB=$'\t' 
(printf "$FORMAT" "REPOSITORY" "PACKAGE" "COVERAGE" &&
    for REPO in $REPOS; do
        REPO_OPT=${REPO:0:1}
        if [ "$REPO_OPT" == "-" ]; then
            REPO=${REPO:1}
        fi
        >&2 echo "Evaluating $REPO ..."
        if [ -r $REPO/go.mod ]; then
            RESET_DIR=$(pwd)
            TOTAL=0
            TOTAL_COUNT=0
            RESULT=0
            cd $REPO;
            VENDOR_FLAG=
            if [ -r vendor ]; then
                VENDOR_FLAG="-mod=vendor"
            fi
            for LINE in $(go test $VENDOR_FLAG -covermode count ./... | grep -i "^\(\?\|OK\)" | sed -e 's/  */__SPACE__/g' -e "s/${TAB}/,/g"); do
                RESULT=$?
                if [ $RESULT -ne 0 ]; then
                    break
                fi
                PKG=$(echo $LINE | /usr/bin/awk -F, '{print $2}' | sed -e "s,github.com/opencord/$REPO/,,g")
                COVERAGE=$(echo $LINE | awk -F, '{print $NF}' | sed -e 's/__SPACE__/ /g')
                if [ "$COVERAGE" != "[no test files]" ]; then
                    COVERAGE=$(echo $COVERAGE | awk '{print $2}' | sed -e 's/%//g')
                else
                    COVERAGE="0"
                fi
                TOTAL=$(python -c "print $TOTAL + $COVERAGE")
                TOTAL_COUNT=$(expr $TOTAL_COUNT + 1)
                printf "$FORMAT" "$REPO" "$PKG" "$(printf '%5.1f%%' $COVERAGE)"
            done
            cd $RESET_DIR
            if [ $RESULT -eq 0 ]; then
                CMD="print \"%5.1f%%\" % ($TOTAL / $TOTAL_COUNT)"
                printf "$FORMAT" "$REPO" "=====" "$(python -c "$CMD")"
            else
                printf "$FORMAT" "$REPO" "*** ERROR ***" "*** ERROR ***"
            fi
        elif [ "$REPO_OPT" != "-" ]; then
            WORK=/tmp/tttt
            rm -rf $WORK
            mkdir -p $WORK/src/github.com/opencord
            ln -s $(pwd)/$REPO $WORK/src/github.com/opencord/$REPO
            RESET_DIR=$(pwd)
            TOTAL=0
            TOTAL_COUNT=0
            RESULT=0
            cd $WORK/src/github.com/opencord/$REPO
            LINES=$(GOPATH=$WORK go test -covermode count ./... | grep -i "^\(\?\|OK\)" | sed -e 's/  */__SPACE__/g' -e "s/${TAB}/,/g")
            RESULT=$?
            if [ $RESULT -eq 0 ]; then
                for LINE in $LINES; do
                    PKG=$(echo $LINE | /usr/bin/awk -F, '{print $2}' | sed -e "s,github.com/opencord/$REPO/,,g")
                    COVERAGE=$(echo $LINE | awk -F, '{print $NF}' | sed -e 's/__SPACE__/ /g')
                    if [ "$COVERAGE" != "[no test files]" ]; then
                        COVERAGE=$(echo $COVERAGE | awk '{print $2}'| sed -e 's/%//g')
                    else
                        COVERAGE="0"
                    fi
                    TOTAL=$(python -c "print $TOTAL + $COVERAGE")
                    TOTAL_COUNT=$(expr $TOTAL_COUNT + 1)
                    printf "$FORMAT" "$REPO" "$PKG" "$(printf '%5.1f%%' $COVERAGE)"
                done
            fi
            cd $RESET_DIR
            if [ $RESULT -eq 0 ]; then
                CMD="print \"%5.1f%%\" % ($TOTAL / $TOTAL_COUNT)"
                printf "$FORMAT" "$REPO" "=====" "$(python -c "$CMD")"
            else
                printf "$FORMAT" "$REPO" "*** ERROR ***" "*** ERROR ***"
            fi
        else
            # Python
            RESET_DIR=$(pwd)
            cd $REPO
            LINES=$(bash -c "make test 2>&1 | awk 'BEGIN{S=-1};{if (S==1 && !/^-+$/) print}; /^-+$/{S=-S; if (S==-1) exit}' | sed -e 's/[\t ][\t ]*/,/g'")
            CUR_PKG=
            PKG_COVERAGE=0
            PKG_COUNT=0
            TOTAL=0
            TOTAL_COUNT=0
            for LINE in $LINES; do
                STMTS=$(echo $LINE | cut -d, -f2)
                if [ $STMTS -eq 0 ]; then
                    continue
                fi
                FILE=$(echo $LINE | cut -d, -f1)
                PKG=$(dirname $FILE)
                if [ "$CUR_PKG X" != " X" -a "$CUR_PKG" != "$PKG" ]; then
                    if [ $PKG_COUNT -ne 0 ]; then
                        printf "$FORMAT" "$REPO" "$CUR_PKG" "$(printf '%5.1f%%' $(expr $PKG_COVERAGE / $PKG_COUNT))"
                        TOTAL=$(python -c "print $TOTAL + $PKG_COVERAGE / $PKG_COUNT")
                    fi
                    TOTAL_COUNT=$(expr $TOTAL_COUNT + 1)
                    PKG_COUNT=0
                    PKG_COVERAGE=0
                fi
                COVERAGE=$(echo $LINE | cut -d, -f6 | head -c -2)
                PKG_COUNT=$(expr $PKG_COUNT + 1)
                PKG_COVERAGE=$(expr $PKG_COVERAGE + $COVERAGE)
                CUR_PKG=$PKG
            done
            cd $RESET_DIR
            if [ $TOTAL_COUNT -eq 0 ]; then
                printf "$FORMAT" "$REPO" "=====" "*** NO TESTS ***"
            else 
                CMD="print \"%5.1f%%\" % ($TOTAL / $TOTAL_COUNT)"
                printf "$FORMAT" "$REPO" "=====" "$(python -c "$CMD")"
            fi
        fi
    done) | column -tx '-s|'
