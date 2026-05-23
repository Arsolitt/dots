#!/usr/bin/env fish
# Bulk-delete VictoriaLogs logs in steps, directly on the cluster vlstorage. AUTONOMOUS.
# Per chunk: launch delete -> wait. On "cannot proceed" (disk too small for the rewrite):
#   cancel the task, shrink the window start forward by SHRINK_SECONDS, retry. Never exits on a stall.
#   If a whole STEP worth of shrinking still won't delete -> disk is genuinely full: back off and retry.
#
# NOTE: uses full `kubectl` (interactive `k`/`kl` are abbreviations that do NOT expand in scripts).
# Run with:  fish vl-purge.fish     (set DRY_RUN=true to preview the windows without deleting)

# ---------------- config ----------------
set -l KCTX           --context arsolitt@psclp-infra   # context safety; remove if your kubectl context is already pinned
set -l POD            nmt                             # debug pod that has curl (add --namespace below if not in current ns)
set -l VLSTORAGE_URL  http://vlstorage-main.logs.svc:9491
set -l LOG_NS         logs                            # namespace of the vlstorage pod
set -l LOG_POD        vlstorage-main-0                # vlstorage pod whose logs we grep for "cannot proceed"
# Scope of deletion. Narrow to etl only by appending the field filters, e.g.:
#   set -l STREAM_FILTER '{cluster="psclp-dev"} kubernetes.container_name:="etl" kubernetes.pod_namespace:="ock-backend"'
set -l STREAM_FILTER  '{cluster="psclp-dev"}'
set -l END_TS         "2026-05-27T23:59:59+03:00"    # fixed end of the interval (MSK; change +03:00 if not MSK)
set -l START_TS       "2026-05-27T09:44:00+03:00"    # initial start of the interval
set -l FLOOR_TS       "2026-05-26T00:00:00+03:00"    # stop when start reaches this (midnight May 26)
set -l STEP_SECONDS   120                            # move start back by this much per successful chunk
set -l SHRINK_SECONDS 15                             # on STUCK: move start FORWARD by this, shrinking the window
set -l POLL_SECONDS   10                             # poll interval for active_tasks / logs
set -l LOG_LOOKBACK   30s                            # how far back to grep vlstorage logs for the stuck pattern
set -l CHUNK_TIMEOUT  900                            # if a task neither finishes nor logs "cannot proceed" in this many s -> treat as stuck
set -l WALL_BACKOFF   60                             # disk-wall: seconds to wait before retrying when even small slices won't delete
set -l MAX_LAUNCH_FAILS 5                            # consecutive run_task failures (API/exec broken) before aborting
set -l DRY_RUN        false                          # true = print commands only; false = actually delete

set -l MAX_SHRINKS    (math --scale=0 "$STEP_SECONDS / $SHRINK_SECONDS * 2")  # shrinking a full step == back to previous frontier

# ---------------- helper: epoch -> MSK wall-clock with +03:00 ----------------
function __fmt_msk --argument-names e
    set -l shifted (math $e + 10800)                 # MSK = UTC + 3h
    set -l wall (date --utc --date="@$shifted" "+%Y-%m-%dT%H:%M:%S")
    echo $wall"+03:00"
end

# ---------------- precompute epochs ----------------
set -l end_epoch   (date --date="$END_TS"   +%s)
set -l floor_epoch (date --date="$FLOOR_TS" +%s)
set -l cur_start   (date --date="$START_TS" +%s)

if test -z "$end_epoch" -o -z "$floor_epoch" -o -z "$cur_start"
    echo "ERROR: failed to parse timestamps" >&2
    exit 1
end

set -l end_str (__fmt_msk $end_epoch)
set -l chunks  (math --scale=0 "($cur_start - $floor_epoch) / $STEP_SECONDS + 1")

echo "Filter   : $STREAM_FILTER"
echo "Window   : start "(__fmt_msk $cur_start)" -> floor "(__fmt_msk $floor_epoch)", end fixed at $end_str"
echo "Stepping : "$STEP_SECONDS"s back / chunk, shrink "$SHRINK_SECONDS"s on stuck (max $MAX_SHRINKS), DRY_RUN=$DRY_RUN"
echo "Chunks   : ~$chunks (more if stalls force retries)"
echo

set -l launch_fails 0

while test $cur_start -ge $floor_epoch
    set -l chunk_target $cur_start          # intended start for this chunk (before any shrinking)
    set -l shrinks 0

    # try to delete [cur_start, end]; on stuck shrink cur_start forward and retry
    while true
        set -l start_str (__fmt_msk $cur_start)
        set -l filter "$STREAM_FILTER _time:[$start_str, $end_str]"
        echo "window [$start_str .. $end_str]"

        if test "$DRY_RUN" = true
            echo "    DRY: kubectl exec $KCTX $POD -- curl --silent --data-urlencode 'filter=$filter' $VLSTORAGE_URL/delete/run_task"
            break
        end

        # --- launch delete task ---
        set -l resp (kubectl exec $KCTX $POD -- curl --silent --data-urlencode "filter=$filter" $VLSTORAGE_URL/delete/run_task)
        set -l task_id (string match --regex --groups-only '"task_id":"([0-9]+)"' -- "$resp")
        if test -z "$task_id"
            set launch_fails (math $launch_fails + 1)
            echo "    WARN: no task_id (fail $launch_fails/$MAX_LAUNCH_FAILS): $resp" >&2
            if test $launch_fails -ge $MAX_LAUNCH_FAILS
                echo "    FATAL: repeated run_task failures — API/exec problem (not a disk stall). Aborting." >&2
                exit 1
            end
            sleep $POLL_SECONDS
            continue
        end
        set launch_fails 0
        echo "    task_id=$task_id, waiting..."

        # --- wait: done | stuck (timeout counts as stuck) ---
        set -l outcome ""
        set -l waited 0
        while true
            sleep $POLL_SECONDS
            set waited (math $waited + $POLL_SECONDS)
            set -l active (kubectl exec $KCTX $POD -- curl --silent $VLSTORAGE_URL/delete/active_tasks)
            if not string match --quiet "*$task_id*" -- $active
                set outcome done
                break
            end
            if kubectl logs $KCTX --namespace $LOG_NS $LOG_POD --since=$LOG_LOOKBACK 2>/dev/null \
                | grep --quiet "cannot proce.*task_id=\"$task_id\""
                set outcome stuck
                break
            end
            if test $waited -ge $CHUNK_TIMEOUT
                set outcome stuck
                break
            end
        end

        if test "$outcome" = done
            echo "    done in ~"$waited"s"
            break
        end

        # --- stuck: cancel the task, then shrink & retry ---
        echo "    STUCK task=$task_id -> cancelling, shrinking by "$SHRINK_SECONDS"s" >&2
        kubectl exec $KCTX $POD -- curl --silent --request POST "$VLSTORAGE_URL/delete/stop_task?task_id=$task_id" >/dev/null
        # wait until the cancelled task disappears (cap ~60s) so we don't run two at once
        set -l cwait 0
        while true
            sleep $POLL_SECONDS
            set cwait (math $cwait + $POLL_SECONDS)
            set -l active (kubectl exec $KCTX $POD -- curl --silent $VLSTORAGE_URL/delete/active_tasks)
            if not string match --quiet "*$task_id*" -- $active
                break
            end
            if test $cwait -ge 60
                echo "    (warn: task $task_id still active 60s after stop; continuing)" >&2
                break
            end
        end

        set shrinks (math $shrinks + 1)
        if test $shrinks -gt $MAX_SHRINKS
            echo "    DISK WALL near "(__fmt_msk $chunk_target)": shrank a full step, still cannot delete." >&2
            echo "    => disk too full for any rewrite. Backing off "$WALL_BACKOFF"s and retrying this chunk (no exit)." >&2
            sleep $WALL_BACKOFF
            set cur_start $chunk_target
            set shrinks 0
            continue
        end

        set cur_start (math $cur_start + $SHRINK_SECONDS)
        if test $cur_start -ge $end_epoch
            echo "    nothing left to delete in this chunk; moving on"
            break
        end
    end

    # advance to the next (older) chunk, measured from the original target
    if test $chunk_target -le $floor_epoch
        break
    end
    set -l next (math $chunk_target - $STEP_SECONDS)
    if test $next -lt $floor_epoch
        set next $floor_epoch
    end
    set cur_start $next
end

echo
echo "Finished at floor "(__fmt_msk $floor_epoch)
