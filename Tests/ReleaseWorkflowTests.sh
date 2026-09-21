#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
workflow_path="$repo_root/.github/workflows/release.yml"

[[ -f "$workflow_path" ]] || {
  echo "Release workflow is missing" >&2
  exit 1
}

ruby - "$workflow_path" <<'RUBY'
require "yaml"
require "open3"

path = ARGV.fetch(0)
workflow = YAML.safe_load(File.read(path), aliases: true)
raise "contents permission must be write" unless workflow.fetch("permissions") == {"contents" => "write"}

events = workflow.fetch("on")
raise "push trigger missing" unless events.key?("push")
raise "manual trigger missing" unless events.key?("workflow_dispatch")
raise "untrusted pull request trigger present" if events.key?("pull_request") || events.key?("pull_request_target")
raise "push branch must be main" unless events.fetch("push").fetch("branches") == ["main"]
raise "push path must be the version plist" unless events.fetch("push").fetch("paths") == ["Packaging/Info.plist"]

publish_input = events.fetch("workflow_dispatch").fetch("inputs").fetch("publish")
raise "manual publication must default off" unless publish_input.fetch("type") == "boolean" && publish_input.fetch("default") == false

jobs = workflow.fetch("jobs")
raise "workflow must have one release job" unless jobs.keys == ["release"]
job = jobs.fetch("release")
raise "wrong runner" unless job.fetch("runs-on") == "macos-15"
raise "automatic publication gate missing" unless job.fetch("env").fetch("SHOULD_PUBLISH").include?("vars.RELEASES_ENABLED")

steps = job.fetch("steps")
steps.each do |step|
  script = step["run"]
  next unless script
  _, syntax_error, status = Open3.capture3("bash", "-n", stdin_data: script)
  raise "invalid shell in #{step.fetch("name")}: #{syntax_error}" unless status.success?
  raise "patch artifact in #{step.fetch("name")}" if script.match?(/\s\+\s+(?:--|https:)/)
end
checkout = steps.find { |step| step["uses"]&.start_with?("actions/checkout@") }
raise "checkout missing full history" unless checkout&.dig("with", "fetch-depth") == 0
raise "checkout action is not the reviewed release" unless checkout.fetch("uses") == "actions/checkout@v7.0.1"

secret_steps = steps.select { |step| step.fetch("env", {}).key?("SPARKLE_PRIVATE_KEY") }
raise "Sparkle secret must be scoped to one step" unless secret_steps.length == 1
raise "Sparkle secret must be scoped to packaging" unless secret_steps.first.fetch("name") == "Package release artifacts"

draft_index = steps.index { |step| step["name"] == "Create or resume draft release" }
publish_index = steps.index { |step| step["name"] == "Publish release" }
verify_index = steps.index { |step| step["name"] == "Verify public release assets" }
raise "draft publication steps missing" unless draft_index && publish_index && verify_index
raise "release published before draft assets" unless draft_index < publish_index && publish_index < verify_index

draft_script = steps.fetch(draft_index).fetch("run")
raise "draft creation missing" unless draft_script.include?("gh release create") && draft_script.include?("--draft")
raise "immutable tag check missing" unless draft_script.include?("git ls-remote")
raise "draft target check missing" unless draft_script.include?("target_commitish") && draft_script.include?("GITHUB_SHA")
raise "asset replacement is forbidden" if draft_script.include?("--clobber")

publish_script = steps.fetch(publish_index).fetch("run")
raise "draft is never published" unless publish_script.include?("--draft=false")
RUBY

echo "Release workflow contract checks passed"
