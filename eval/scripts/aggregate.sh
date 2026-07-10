#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s <runId>\n' "$(basename "$0")" >&2
}

die() {
  printf 'aggregate: %s\n' "$1" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

run_id="$1"
if [[ -z "$run_id" || "$run_id" == /* || "$run_id" == *"/"* || "$run_id" == *".."* ]]; then
  die "runId must be a single path segment"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$script_dir/../.."
run_dir="$repo_root/eval/results/$run_id"
raw_dir="$run_dir/raw"
map_file="$raw_dir/de-anonymization-map.json"
scorecard_json="$run_dir/scorecard.json"
scorecard_md="$run_dir/scorecard.md"

[[ -d "$raw_dir" ]] || die "raw score directory not found: $raw_dir"

shopt -s nullglob
raw_files=("$raw_dir"/*.json)
shopt -u nullglob

if [[ ${#raw_files[@]} -eq 0 ]]; then
  die "no raw JSON files found in $raw_dir"
fi

# De-anonymization contract:
# - canonical path: eval/results/<runId>/raw/de-anonymization-map.json
# - producer: the eval-runner session, before blind judge dispatch
# - schema: {"mappings":[{"taskId":string,"track":"A"|"B",
#   "candidateModels":{"A":string,"B":string,"C":string}}]}
[[ -f "$map_file" ]] || die "de-anonymization map not found: $map_file"

score_files=()
for raw_file in "${raw_files[@]}"; do
  if [[ "$raw_file" != "$map_file" ]]; then
    score_files+=("$raw_file")
  fi
done

if [[ ${#score_files[@]} -eq 0 ]]; then
  die "no raw score JSON files found in $raw_dir"
fi

mkdir -p "$run_dir"

manifest_records="$(mktemp)"
corpus_manifest="$(mktemp)"
scorecard_tmp="$(mktemp)"
cleanup() {
  rm -f "$manifest_records" "$corpus_manifest" "$scorecard_tmp"
}
trap cleanup EXIT

# Corpus layout is the only source of truth for task identity and kind.
for task_dir in "$repo_root"/eval/corpus/*/*; do
  [[ -d "$task_dir" ]] || continue
  task_id="${task_dir#"$repo_root/eval/corpus/"}"
  domain="${task_id%%/*}"
  if [[ -d "$task_dir/tests" ]]; then
    kind="code"
  else
    kind="taste"
  fi
  jq -cn \
    --arg taskId "$task_id" \
    --arg domain "$domain" \
    --arg kind "$kind" \
    '{taskId: $taskId, domain: $domain, kind: $kind}' >>"$manifest_records"
done
jq -s '.' "$manifest_records" >"$corpus_manifest"

# Combined scoring rule, matching docs/11-routing-eval.md:
# - CODE domains are correctness-gated. A task/model/track receives its judge
#   quality score only when correctness is 1.0. At the domain/track level, any
#   code task below full correctness makes that model's combined score 0 for the
#   domain, so a model that does not pass tests cannot compete with passing
#   output. Track A ranks the domain because Track A is the production wrapper
#   path.
# - TASTE domains have no objective tests. The rubric/judge quality score is
#   the entire combined score, averaged across tasks for the domain.
# For every model, wrapperDelta is Track A combined minus Track B combined.
if ! jq \
  --arg runId "$run_id" \
  --slurpfile corpus "$corpus_manifest" \
  --slurpfile mapDocument "$map_file" \
  -s '
  def round6:
    if . == null then null else ((. * 1000000 | round) / 1000000) end;

  def avg:
    if length == 0 then null else (add / length) end;

  def require($condition; $message):
    if $condition then . else error($message) end;

  def flattened:
    [ .[] | if type == "array" then .[] else . end ];

  ($corpus[0]) as $tasks
  | require(
      ($mapDocument | length) == 1;
      "invalid de-anonymization map schema"
    )
  | ($mapDocument[0]) as $mapDoc
  | require(
      ($mapDoc | type == "object")
      and (($mapDoc | keys | sort) == ["mappings"])
      and (($mapDoc.mappings | type) == "array")
      and (($mapDoc.mappings | length) > 0);
      "invalid de-anonymization map schema"
    )
  | ($mapDoc.mappings) as $mappings
  | require(
      all($mappings[];
        (type == "object")
        and ((keys | sort) == ["candidateModels", "taskId", "track"])
        and ((.taskId | type) == "string")
        and (.taskId | length) > 0
        and (.track == "A" or .track == "B")
        and ((.candidateModels | type) == "object")
        and ((.candidateModels | keys | sort) == ["A", "B", "C"])
        and all(.candidateModels[]; (type == "string") and length > 0)
        and (([.candidateModels.A, .candidateModels.B, .candidateModels.C] | unique | length) == 3)
      );
      "invalid de-anonymization map entry"
    )
  | require(
      ([
        $mappings
        | group_by([.taskId, .track])[]
        | select(length > 1)
      ] | length) == 0;
      "duplicate de-anonymization map identity"
    )
  | require(
      ([
        $mappings[]
        | .taskId as $taskId
        | select(any($tasks[]; .taskId == $taskId) | not)
      ] | length) == 0;
      "unknown taskId in de-anonymization map"
    )
  | require(
      all(($mappings | group_by(.taskId)[]);
        (length == 2) and ((map(.track) | sort) == ["A", "B"])
      );
      "each mapped task requires exactly Track A and Track B"
    )
  | require(
      all(($mappings | group_by(.taskId)[]);
        ([
          .[]
          | [.candidateModels.A, .candidateModels.B, .candidateModels.C]
          | sort
        ] | unique | length) == 1
      );
      "candidate model identities differ between tracks"
    )
  | flattened as $records
  | ($records | map(
      if type != "object" then
        error("malformed raw score record")
      elif has("judge") or has("scores") or has("rationale") then
        . + {_recordType: "panel"}
      elif has("model") or has("passed") or has("total") or has("correctness") then
        . + {_recordType: "objective"}
      else
        error("unrecognized raw score record")
      end
    )) as $typedRecords
  | ($typedRecords | map(select(._recordType == "panel"))) as $panels
  | ($typedRecords | map(select(._recordType == "objective"))) as $objectives
  | require(
      all($panels[];
        ((.judge | type) == "string")
        and (.judge as $judge | ["codex", "grok", "opus"] | index($judge) != null)
        and ((.taskId | type) == "string")
        and (.taskId | length) > 0
        and (.track == "A" or .track == "B")
        and ((.scores | type) == "object")
        and ((.scores | keys | sort) == ["A", "B", "C"])
        and all(.scores[]; (type == "number") and . >= 0 and . <= 5)
        and ((.rationale | type) == "string")
      );
      "malformed judge panel"
    )
  | require(
      ([
        $panels[]
        | .taskId as $taskId
        | select(any($tasks[]; .taskId == $taskId) | not)
      ] | length) == 0;
      "unknown taskId in judge panel"
    )
  | require(
      all($panels[];
        . as $panel
        | any($mappings[];
          .taskId == $panel.taskId and .track == $panel.track
        )
      );
      "judge panel has no de-anonymization map entry"
    )
  | require(
      all($panels[];
        . as $panel
        | if ($panel | has("candidateModels")) then
          any($mappings[];
            .taskId == $panel.taskId
            and .track == $panel.track
            and .candidateModels == $panel.candidateModels
          )
        else
          true
        end
      );
      "inline candidateModels conflicts with de-anonymization map"
    )
  | require(
      ([
        $panels
        | group_by([.taskId, .track, .judge])[]
        | select(length > 1)
      ] | length) == 0;
      "duplicate judge panel identity"
    )
  | require(
      all($mappings[];
        . as $mapping
        | ([
          $panels[]
          | select(
              .taskId == $mapping.taskId
              and .track == $mapping.track
            )
          | .judge
        ] | sort) == ["codex", "grok", "opus"]
      );
      "incomplete judge panel"
    )
  | require(
      all($objectives[];
        ((.taskId | type) == "string")
        and (.taskId | length) > 0
        and ((.model | type) == "string")
        and (.model | length) > 0
        and (.track == "A" or .track == "B")
        and ((.passed | type) == "number")
        and (.passed >= 0)
        and (.passed == (.passed | floor))
        and ((.total | type) == "number")
        and (.total > 0)
        and (.total == (.total | floor))
        and (.passed <= .total)
        and ((.correctness | type) == "number")
        and (.correctness >= 0)
        and (.correctness <= 1)
        and (.correctness == (.passed / .total))
      );
      "malformed objective record"
    )
  | require(
      ([
        $objectives[]
        | .taskId as $taskId
        | select(any($tasks[]; .taskId == $taskId) | not)
      ] | length) == 0;
      "unknown taskId in objective record"
    )
  | require(
      all($objectives[];
        . as $objective
        | any($mappings[];
          .taskId == $objective.taskId
          and .track == $objective.track
          and ([.candidateModels.A, .candidateModels.B, .candidateModels.C] | index($objective.model) != null)
        )
      );
      "objective record does not match mapped candidate"
    )
  | require(
      ([
        $objectives
        | group_by([.taskId, .track, .model])[]
        | select(length > 1)
      ] | length) == 0;
      "duplicate objective identity"
    )
  | require(
      all($objectives[];
        . as $objective
        | any($tasks[];
          .taskId == $objective.taskId and .kind == "code"
        )
      );
      "taste task has objective record"
    )
  | require(
      all($mappings[];
        . as $mapping
        | ([
          $tasks[]
          | select(.taskId == $mapping.taskId)
          | .kind
        ][0]) as $kind
        | if $kind == "code" then
            all(
              [$mapping.candidateModels.A, $mapping.candidateModels.B, $mapping.candidateModels.C][];
              . as $model
              | ([
                $objectives[]
                | select(
                    .taskId == $mapping.taskId
                    and .track == $mapping.track
                    and .model == $model
                  )
              ] | length) == 1
            )
          else
            true
          end
      );
      "missing code objective record"
    )
  | ([
      $panels[] as $panel
      | ($mappings[]
          | select(
              .taskId == $panel.taskId
              and .track == $panel.track
            )) as $mapping
      | $panel.scores
      | to_entries[]
      | {
          taskId: $panel.taskId,
          model: $mapping.candidateModels[.key],
          track: $panel.track,
          quality: .value
        }
    ]) as $quality
  | ([
      $quality
      | group_by([.taskId, .model, .track])[]
      | . as $group
      | ($tasks[] | select(.taskId == $group[0].taskId)) as $task
      | ([
          $objectives[]
          | select(
              .taskId == $group[0].taskId
              and .model == $group[0].model
              and .track == $group[0].track
            )
          | .correctness
        ][0] // null) as $correctness
      | {
          taskId: $group[0].taskId,
          domain: $task.domain,
          kind: $task.kind,
          model: $group[0].model,
          track: $group[0].track,
          correctness: ($correctness | round6),
          quality: ($group | map(.quality) | avg | round6),
          combined: (
            if $task.kind == "code" then
              if $correctness >= 1 then
                ($group | map(.quality) | avg)
              else
                0
              end
            else
              ($group | map(.quality) | avg)
            end
            | round6
          )
        }
    ]) as $taskScores
  | (
      $taskScores
      | sort_by(.domain, .model, .track)
      | group_by([.domain, .model, .track])
      | map(
          {
            domain: .[0].domain,
            kind: .[0].kind,
            model: .[0].model,
            track: .[0].track,
            combined: (
              if .[0].kind == "code" and any(.[]; .correctness < 1) then
                0
              else
                (map(.combined) | avg)
              end
              | round6
            ),
            correctness: (
              if .[0].kind == "code" then
                (map(.correctness) | avg | round6)
              else
                null
              end
            ),
            quality: (map(.quality) | avg | round6)
          }
        )
    ) as $trackScores
  | {
      runId: $runId,
      domains: (
        reduce (([$trackScores[].domain] | unique)[]) as $domain ({ };
          .[$domain] = (
            ([
              $trackScores[]
              | select(.domain == $domain and .track == "A")
              | {model, combined, correctness, quality}
            ] | sort_by(-.combined, .model)) as $ranking
            | {
                ranking: $ranking,
                margin: (
                  if ($ranking | length) >= 2 then
                    (($ranking[0].combined - $ranking[1].combined) | round6)
                  else
                    null
                  end
                ),
                wrapperDelta: (
                  reduce (([
                    $trackScores[]
                    | select(.domain == $domain)
                    | .model
                  ] | unique)[]) as $model ({ };
                    .[$model] = (
                      ([$trackScores[] | select(.domain == $domain and .model == $model and .track == "A") | .combined][0]) as $trackA
                      | ([$trackScores[] | select(.domain == $domain and .model == $model and .track == "B") | .combined][0]) as $trackB
                      | (($trackA - $trackB) | round6)
                    )
                  )
                )
              }
          )
        )
      )
    }
  ' "${score_files[@]}" >"$scorecard_tmp"; then
  die "dataset preflight failed"
fi

mv "$scorecard_tmp" "$scorecard_json"

jq -r '
  def cell:
    if . == null then "n/a" else tostring end;

  "# Routing Eval Scorecard",
  "",
  ("Run: `" + .runId + "`"),
  "",
  (
    .domains
    | to_entries
    | sort_by(.key)[]
    | .key as $domainName
    | .value as $domain
    | "## " + $domainName,
      "",
      ("Margin: " + ($domain.margin | cell)),
      "",
      "| Rank | Model | Combined | Correctness | Quality | Delta(A-B) |",
      "|---:|---|---:|---:|---:|---:|",
      (
        $domain.ranking
        | to_entries[]
        | . as $ranked
        | $ranked.value as $row
        | "| "
          + (($ranked.key + 1) | tostring)
          + " | "
          + $row.model
          + " | "
          + ($row.combined | cell)
          + " | "
          + ($row.correctness | cell)
          + " | "
          + ($row.quality | cell)
          + " | "
          + ($domain.wrapperDelta[$row.model] | cell)
          + " |"
      ),
      ""
  )
' "$scorecard_json" >"$scorecard_md"
