learning_intake_report_date() {
  local report_name="$1"
  local year month day
  if [[ "$report_name" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})- ]]; then
    year="${BASH_REMATCH[1]}"
    month="${BASH_REMATCH[2]}"
    day="${BASH_REMATCH[3]}"
  elif [[ "$report_name" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})- ]]; then
    year="${BASH_REMATCH[1]}"
    month="${BASH_REMATCH[2]}"
    day="${BASH_REMATCH[3]}"
  else
    return 1
  fi
  [[ "$month" =~ ^(0[1-9]|1[0-2])$ && "$day" =~ ^(0[1-9]|[12][0-9]|3[01])$ ]] || return 1
  printf '%s-%s-%s' "$year" "$month" "$day"
}

cmd_doctor_intake() {
  local inbox_dir="$WORKSPACE_DIR/tmp/learning-intake"
  local pending_count=0 deferred_count=0 unreadable_count=0 undated_count=0
  local oldest_date="" report_file report_date grep_status listing

  if [ -d "$inbox_dir" ]; then
    if ! listing=$(find "$inbox_dir" -maxdepth 1 -name '*.md' ! -name '.*' 2>/dev/null); then
      warn "learning-intake: tmp/learning-intake/ を一覧できません（件数を数えていません）"
      return 0
    fi
    while IFS= read -r report_file; do
      [ -n "$report_file" ] && [ -f "$report_file" ] || continue
      grep_status=0
      grep -q '^status: 保留[[:space:]]*$' "$report_file" 2>/dev/null || grep_status=$?
      if [ "$grep_status" -eq 0 ]; then
        deferred_count=$((deferred_count + 1))
      elif [ "$grep_status" -ge 2 ]; then
        unreadable_count=$((unreadable_count + 1))
      else
        pending_count=$((pending_count + 1))
        if report_date=$(learning_intake_report_date "${report_file##*/}"); then
          if [ -z "$oldest_date" ] || [[ "$report_date" < "$oldest_date" ]]; then
            oldest_date="$report_date"
          fi
        else
          undated_count=$((undated_count + 1))
        fi
      fi
    done <<<"$listing"
  fi

  printf 'learning-intake inbox: 未処理 %s / 保留 %s\n' "$pending_count" "$deferred_count"
  if [ "$pending_count" -gt 0 ] && [ -n "$oldest_date" ]; then
    printf '  最古の未処理: %s\n' "$oldest_date"
  fi
  if [ "$undated_count" -gt 0 ]; then
    printf '  日付不明: %s 件\n' "$undated_count"
  fi
  if [ "$unreadable_count" -gt 0 ]; then
    warn "learning-intake: 読み取り不能な報告 $unreadable_count 件（未処理・保留の件数に含めていない）"
  fi
  if [ "$pending_count" -ge "$LEARNING_INTAKE_PENDING_WARN_THRESHOLD" ]; then
    warn "learning-intake: 未処理 $pending_count 件が溜まっています（閾値 $LEARNING_INTAKE_PENDING_WARN_THRESHOLD）。tmp/learning-intake/ を learning-intake の受入れ経路で処理してください"
  fi
}
