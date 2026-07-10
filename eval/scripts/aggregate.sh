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
scorecard_json="$run_dir/scorecard.json"
scorecard_md="$run_dir/scorecard.md"

[[ -d "$raw_dir" ]] || die "raw score directory not found: $raw_dir"

shopt -s nullglob
raw_files=("$raw_dir"/*.json)
shopt -u nullglob

if [[ ${#raw_files[@]} -eq 0 ]]; then
  die "no raw JSON files found in $raw_dir"
fi

mkdir -p "$run_dir"

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
jq --arg runId "$run_id" -s '
  def round6:
    if . == null then null else ((. * 1000000 | round) / 1000000) end;

  def avg:
    if length == 0 then null else (add / length) end;

  def domain_of:
    .domain // (.taskId | split("/")[0]);

  def flattened:
    [ .[] | if type == "array" then .[] else . end ];

  def per_model_quality_records($records):
    [
      $records[]
      | select(
          has("taskId")
          and has("model")
          and has("track")
          and (has("quality") or has("rubricScore") or has("score"))
        )
      | {
          taskId,
          domain: domain_of,
          model,
          track,
          quality: (.quality // .rubricScore // .score)
        }
    ];

  def mapped_panel_quality_records($records):
    [
      $records[]
      | select(
          has("taskId")
          and has("track")
          and has("scores")
          and has("candidateModels")
        )
      | . as $record
      | $record.scores
      | to_entries[]
      | {
          taskId: $record.taskId,
          domain: ($record.domain // ($record.taskId | split("/")[0])),
          model: $record.candidateModels[.key],
          track: $record.track,
          quality: .value
        }
      | select(.model != null)
    ];

  flattened as $records
  | (
      [
        $records[]
        | select(
            has("taskId")
            and has("model")
            and has("track")
            and (has("correctness") or (has("passed") and has("total")))
          )
        | {
            taskId,
            domain: domain_of,
            model,
            track,
            correctness: (
              if has("correctness") then
                .correctness
              elif (.total | tonumber) > 0 then
                ((.passed | tonumber) / (.total | tonumber))
              else
                0
              end
            )
          }
      ]
    ) as $objective
  | ((per_model_quality_records($records) + mapped_panel_quality_records($records))) as $quality
  | (
      ($objective + $quality)
      | map({ taskId, domain, model, track })
      | unique_by([.taskId, .domain, .model, .track])
      | map(
          . as $combo
          | (
              [
                $objective[]
                | select(
                    .taskId == $combo.taskId
                    and .model == $combo.model
                    and .track == $combo.track
                  )
                | .correctness
              ]
            ) as $correctnessValues
          | (
              [
                $quality[]
                | select(
                    .taskId == $combo.taskId
                    and .model == $combo.model
                    and .track == $combo.track
                  )
                | .quality
              ]
            ) as $qualityValues
          | ($correctnessValues | avg) as $correctness
          | ($qualityValues | avg) as $qualityScore
          | (if any($objective[]; .domain == $combo.domain) then "code" else "taste" end) as $kind
          | {
              taskId: $combo.taskId,
              domain: $combo.domain,
              kind: $kind,
              model: $combo.model,
              track: $combo.track,
              correctness: ($correctness | round6),
              quality: ($qualityScore | round6),
              combined: (
                if $kind == "code" then
                  if (($correctness // 0) >= 1) and ($qualityScore != null) then
                    $qualityScore
                  else
                    0
                  end
                else
                  ($qualityScore // 0)
                end
                | round6
              )
            }
        )
    ) as $taskScores
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
              if .[0].kind == "code" and any(.[]; (.correctness // 0) < 1) then
                0
              else
                (map(.combined) | avg)
              end
              | round6
            ),
            correctness: (
              if .[0].kind == "code" then
                (map(.correctness // 0) | avg | round6)
              else
                null
              end
            ),
            quality: (map(.quality // 0) | avg | round6)
          }
        )
    ) as $trackScores
  | {
      runId: $runId,
      domains: (
        reduce (([$trackScores[].domain] | unique)[]) as $domain ({};
          .[$domain] = (
            (
              [
                $trackScores[]
                | select(.domain == $domain and .track == "A")
                | {
                    model,
                    combined,
                    correctness,
                    quality
                  }
              ]
              | sort_by(-.combined, .model)
            ) as $ranking
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
                  reduce (
                    ([
                      $trackScores[]
                      | select(.domain == $domain)
                      | .model
                    ] | unique)[]
                  ) as $model ({};
                    .[$model] = (
                      ([ $trackScores[] | select(.domain == $domain and .model == $model and .track == "A") | .combined ][0] // null) as $trackA
                      | ([ $trackScores[] | select(.domain == $domain and .model == $model and .track == "B") | .combined ][0] // null) as $trackB
                      | if $trackA != null and $trackB != null then
                          (($trackA - $trackB) | round6)
                        else
                          null
                        end
                    )
                  )
                )
              }
          )
        )
      )
    }
' "${raw_files[@]}" >"$scorecard_json"

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
