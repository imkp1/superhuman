#!/usr/bin/env bash
# Network-free, bash 3.2-clean. Gates on ubuntu and macOS alike.
set -euo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}"
F="$ROOT/scripts/repo-finder/curated_list_filter.sh"

keep() {  # keep <label> <json>
  local rc=0
  printf '%s' "$2" | bash "$F" 2>/dev/null || rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL $1: expected KEEP (exit 0), got exit $rc"; exit 1; }
}
skip() {  # skip <label> <json>
  local rc=0
  printf '%s' "$2" | bash "$F" 2>/dev/null || rc=$?
  [ "$rc" -eq 1 ] || { echo "FAIL $1: expected SKIP (exit 1), got exit $rc"; exit 1; }
}

# --- The three repos that actually topped a default-profile scan. All lists. ---
skip free-programming-books \
  '{"name":"free-programming-books","language":null,"topics":["books","education","list"]}'
skip project-based-learning \
  '{"name":"project-based-learning","language":null,"topics":["tutorial","programming"]}'
# public-apis has a real primary language; weak signals alone must catch it.
skip public-apis \
  '{"name":"public-apis","language":"Python","topics":["api","list","lists","resources","dataset"]}'

# --- Strong signals, each sufficient alone. ---
skip awesome-name-prefix '{"name":"awesome-go","language":"Go","topics":["go"]}'
skip awesome-topic       '{"name":"a-big-list","language":"JavaScript","topics":["awesome"]}'
skip roadmap-topic       '{"name":"developer-roadmap","language":"TypeScript","topics":["roadmap"]}'
skip markdown-language   '{"name":"some-notes","language":"Markdown","topics":["notes"]}'
skip null-language       '{"name":"some-notes","language":null,"topics":[]}'

# --- Real code repos from the same scan must survive. ---
keep pytorch   '{"name":"pytorch","language":"Python","topics":["machine-learning","deep-learning","gpu","tensor"]}'
keep puppeteer '{"name":"puppeteer","language":"TypeScript","topics":["developer-tools","testing","chrome"]}'
keep yt-dlp    '{"name":"yt-dlp","language":"Python","topics":["python","video","youtube-dl"]}'

# --- The false-positive guard, and the whole reason for the strong/weak split.
# A hard skip has no appeal, so ONE weak keyword must never trigger one: real code
# repos legitimately carry a single list-ish topic. ---
keep one-weak-topic-education \
  '{"name":"scikit-learn","language":"Python","topics":["machine-learning","education"]}'
keep one-weak-topic-resources \
  '{"name":"rust-analyzer","language":"Rust","topics":["ide","resources"]}'

# `listing`, `bookkeeping` and `guidelines` each CONTAIN a weak keyword (list, book,
# guide) without being one. This is the yt-dlp/"chains" lesson generalized: match
# whole topics, never substrings.
keep substring-not-token \
  '{"name":"checklist-engine","language":"Go","topics":["listing","bookkeeping","guidelines"]}'

# --- The language-pinned scan. ---
#
# These records are real, from a `languages: go, python` profile. Such a profile
# pins `language:` in every query, so GitHub asserts a primary language on every
# candidate and the `language=null` signal cannot fire — a Markdown course with one
# build script reports as "Python". The topic signals are the whole filter here, and
# a course carries exactly one pedagogy topic, so it must be strong enough alone.
skip course-tutorial-only \
  '{"name":"hello-agents","language":"Python","topics":["agent","llm","rag","tutorial"]}'
skip course-educational \
  '{"name":"learn-claude-code","language":"Python","topics":["agent","claude","educational","llm","teaching","tutorial"]}'
skip course-from-scratch \
  '{"name":"ai-engineering-from-scratch","language":"Python","topics":["ai","course","from-scratch","llm","python","tutorial"]}'

# --- Controls: real, patchable code from the same scan, none of which may be
# skipped. A hard skip has no appeal, so a pedagogy rule that eats a live library is
# worse than the leak it closes. ---
keep deer-flow \
  '{"name":"deer-flow","language":"Python","topics":["agent","agentic","ai","ai-agents","deep-research","harness","langchain","llm","multi-agent","python"]}'
keep llama_index \
  '{"name":"llama_index","language":"Python","topics":["agents","application","data","fine-tuning","framework","llamaindex","llm","rag","vector-database"]}'
keep transformers \
  '{"name":"transformers","language":"Python","topics":["deep-learning","llm","machine-learning","model-hub","nlp","python","pytorch","transformer"]}'
keep LightRAG \
  '{"name":"LightRAG","language":"Python","topics":["genai","gpt","graphrag","knowledge-graph","llm","rag","retrieval-augmented-generation"]}'
keep open-webui \
  '{"name":"open-webui","language":"Python","topics":["ai","llm","llm-ui","mcp","ollama","openai","rag","self-hosted","ui","webui"]}'
keep AstrBot \
  '{"name":"AstrBot","language":"Python","topics":["bot","chatbot","llm","openai","qq","telegram"]}'
keep nanobot \
  '{"name":"nanobot","language":"Python","topics":["agent","ai","llm","mcp"]}'

# A library that ships a `guide` topic, or carries a `learning` tag, is still a
# library. These stay WEAK for exactly that reason: one alone cannot hard-skip.
keep one-weak-topic-guide \
  '{"name":"gin","language":"Go","topics":["web-framework","guide"]}'

# --- Config errors are exit 10, distinct from the SKIP verdict: a caller must be
# able to tell "this repo is a list" from "the filter is broken". ---
rc=0; printf '' | bash "$F" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 10 ] || { echo "FAIL empty stdin: expected exit 10, got $rc"; exit 1; }
rc=0; printf 'not json' | bash "$F" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 10 ] || { echo "FAIL bad json: expected exit 10, got $rc"; exit 1; }

# --- Missing keys must not die under `set -u`. ---
skip no-fields '{"name":"mystery"}'
keep full_name_fallback '{"full_name":"torvalds/linux","language":"C","topics":["kernel"]}'

echo "OK test_curated_list_filter.sh"
