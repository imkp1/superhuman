# Installed Skills — Catalog

Generated: 2026-04-24
Source: skills currently available in this Claude Code session

This is an index of every skill currently loaded, grouped by theme, with a one-line purpose for each. Skill names match what you would type (e.g. `/qa`). Names prefixed with `superpowers:`, `everything-claude-code:`, `frontend-design:`, `ui-ux-pro-max:` live in plugin namespaces.

---

## 1. Core workflow & session management

| Skill | Purpose |
|---|---|
| `init` | Initialize a new CLAUDE.md file with codebase documentation |
| `everything-claude-code:save-session` | Save current session state to a dated file in `~/.claude/session-data/` |
| `everything-claude-code:resume-session` | Load the most recent session file and resume work |
| `everything-claude-code:sessions` | Manage Claude Code session history, aliases, and metadata |
| `context-save` | Save working context (git state, decisions, remaining work) |
| `context-restore` | Restore working context saved earlier by `/context-save` |
| `everything-claude-code:strategic-compact` | Suggest manual context compaction at logical intervals |
| `everything-claude-code:context-budget` | Audit Claude Code context window consumption across agents/skills/MCP |
| `everything-claude-code:token-budget-advisor` | Offer the user an informed choice about response depth |

## 2. Planning, brainstorming, decision-making

| Skill | Purpose |
|---|---|
| `superpowers:brainstorming` | Creative work primer — features, components, spec (use before creative work) |
| `superpowers:writing-plans` | Turn a spec into a written implementation plan |
| `superpowers:executing-plans` | Execute a written implementation plan in a separate session |
| `superpowers:subagent-driven-development` | Execute plans with independent subagent tasks |
| `everything-claude-code:plan` | Restate requirements, assess risks, create step-by-step implementation plan |
| `everything-claude-code:feature-dev` | Guided feature development with codebase understanding |
| `everything-claude-code:blueprint` | Turn a one-line objective into a multi-session construction plan |
| `everything-claude-code:council` | Four-voice council for ambiguous decisions, tradeoffs, go/no-go calls |
| `office-hours` | YC-style forcing questions: demand, startup reality |
| `plan-ceo-review` | CEO/founder-mode plan review — 10-star product thinking, challenge scope |
| `plan-eng-review` | Eng-manager-mode plan review — architecture, data flow, discipline |
| `plan-design-review` | Interactive design plan review — rates designs, designer's eye |
| `plan-devex-review` | Developer experience plan review |
| `plan-tune` | Tune question sensitivity + developer psychographic for gstack |
| `autoplan` | Auto-review pipeline — CEO + design + eng + DX review in one go |
| `everything-claude-code:prp-prd` | Interactive PRD generator — problem-first, hypothesis-driven product spec |
| `everything-claude-code:prp-plan` | Comprehensive feature implementation plan with codebase analysis |
| `everything-claude-code:prp-implement` | Execute an implementation plan with rigorous validation loops |

## 3. Code review & verification

| Skill | Purpose |
|---|---|
| `review` | Pre-landing PR review — SQL safety, LLM truth, diff against base |
| `superpowers:code-reviewer` | Review work against the original plan and coding standards |
| `superpowers:receiving-code-review` | Use when receiving code review feedback |
| `superpowers:requesting-code-review` | Request review before merging |
| `superpowers:verification-before-completion` | Verify before claiming work done |
| `superpowers:finishing-a-development-branch` | Decide how to integrate a completed branch |
| `everything-claude-code:code-review` | Local uncommitted changes or GitHub PR review |
| `everything-claude-code:review-pr` | Comprehensive PR review using specialized agents |
| `everything-claude-code:verification-loop` | Comprehensive verification system for sessions |
| `everything-claude-code:verify` | Legacy shim for verification-loop |
| `codex` | OpenAI Codex wrapper — independent diff review |
| `everything-claude-code:gateguard` | Fact-forcing gate blocking Edit/Write/Bash without evidence |

## 4. Language-specific review

| Skill | Purpose |
|---|---|
| `everything-claude-code:python-review` | Python: PEP 8, type hints, security, Pythonic idioms |
| `everything-claude-code:go-review` | Go: idiomatic, concurrency, error handling |
| `everything-claude-code:rust-review` | Rust: ownership, lifetimes, unsafe, error handling |
| `everything-claude-code:cpp-review` | C++: memory safety, modern idioms, concurrency |
| `everything-claude-code:kotlin-review` | Kotlin: idiomatic, null safety, coroutines |
| `everything-claude-code:flutter-review` | Flutter/Dart: widgets, state management, idioms |
| `everything-claude-code:flutter-dart-code-review` | Library-agnostic Flutter/Dart review checklist |

## 5. Language-specific testing (TDD)

| Skill | Purpose |
|---|---|
| `everything-claude-code:tdd` | Legacy shim for tdd-workflow |
| `everything-claude-code:tdd-workflow` | Write tests first, then code — general TDD workflow |
| `everything-claude-code:go-test` | Go TDD with table-driven tests, 80% coverage |
| `everything-claude-code:rust-test` | Rust TDD with 80% coverage |
| `everything-claude-code:cpp-test` | C++ TDD with GoogleTest |
| `everything-claude-code:kotlin-test` | Kotlin TDD with Kotest, 80% coverage |
| `everything-claude-code:flutter-test` | Flutter/Dart tests — unit, widget, integration |
| `everything-claude-code:python-testing` | pytest patterns, fixtures, mocking, parametrize |
| `everything-claude-code:golang-testing` | Table-driven, subtests, benchmarks, fuzzing |
| `everything-claude-code:rust-testing` | Unit, integration, async, property-based |
| `everything-claude-code:cpp-testing` | GoogleTest/CTest configuration and fixtures |
| `everything-claude-code:kotlin-testing` | Kotest, MockK, coroutine testing |
| `everything-claude-code:csharp-testing` | xUnit, FluentAssertions, mocking |
| `everything-claude-code:perl-testing` | Test2::V0, Test::More, prove, coverage |
| `everything-claude-code:laravel-tdd` | PHPUnit/Pest, factories, DB testing |
| `everything-claude-code:django-tdd` | pytest-django, factory_boy, mocking |
| `everything-claude-code:springboot-tdd` | JUnit 5, Mockito, MockMvc, Testcontainers |
| `everything-claude-code:ai-regression-testing` | Regression testing for AI-assisted development |

## 6. Build / compile / runtime fixers

| Skill | Purpose |
|---|---|
| `everything-claude-code:rust-build` | Fix Rust build, borrow checker, Cargo issues |
| `everything-claude-code:go-build` | Fix Go build, vet, linter issues |
| `everything-claude-code:cpp-build` | Fix C++ build, CMake, linker issues |
| `everything-claude-code:kotlin-build` | Fix Kotlin/Gradle build issues |
| `everything-claude-code:gradle-build` | Fix Gradle for Android/KMP |
| `everything-claude-code:flutter-build` | Fix Dart analyzer and Flutter build failures |

## 7. Language patterns & idioms

| Skill | Purpose |
|---|---|
| `everything-claude-code:python-patterns` | Pythonic idioms, PEP 8, type hints |
| `everything-claude-code:golang-patterns` | Idiomatic Go |
| `everything-claude-code:rust-patterns` | Ownership, error handling, traits, concurrency |
| `everything-claude-code:cpp-coding-standards` | C++ Core Guidelines conformance |
| `everything-claude-code:kotlin-patterns` | Idiomatic Kotlin |
| `everything-claude-code:kotlin-coroutines-flows` | Structured concurrency, Flow patterns |
| `everything-claude-code:kotlin-ktor-patterns` | Ktor DSL, plugins, auth, Koin DI |
| `everything-claude-code:kotlin-exposed-patterns` | Exposed ORM, DSL queries, transactions |
| `everything-claude-code:dart-flutter-patterns` | Null safety, immutable state, async |
| `everything-claude-code:dotnet-patterns` | Idiomatic C#/.NET, DI, async |
| `everything-claude-code:perl-patterns` | Modern Perl 5.36+ idioms |
| `everything-claude-code:swift-concurrency-6-2` | Swift 6.2 Approachable Concurrency |
| `everything-claude-code:swiftui-patterns` | SwiftUI with @Observable, composition |
| `everything-claude-code:swift-actor-persistence` | Thread-safe persistence via actors |
| `everything-claude-code:swift-protocol-di-testing` | Protocol-based DI for testable Swift |
| `everything-claude-code:java-coding-standards` | Java/Spring Boot naming, immutability |
| `everything-claude-code:compose-multiplatform-patterns` | Compose KMP state, composition |
| `everything-claude-code:android-clean-architecture` | Android/KMP Clean Architecture modules |
| `everything-claude-code:coding-standards` | Cross-project baseline conventions |

## 8. Framework patterns

| Skill | Purpose |
|---|---|
| `everything-claude-code:laravel-patterns` | Routing, Eloquent, services, queues |
| `everything-claude-code:laravel-verification` | Laravel verification loop |
| `everything-claude-code:laravel-security` | Laravel auth, CSRF, mass assignment |
| `everything-claude-code:laravel-plugin-discovery` | Evaluate Laravel packages via LaraPlugins.io MCP |
| `everything-claude-code:django-patterns` | DRF, ORM, caching, Celery |
| `everything-claude-code:django-security` | Django auth, CSRF, SQLi, XSS defense |
| `everything-claude-code:django-verification` | Django verification loop |
| `everything-claude-code:nestjs-patterns` | NestJS modules, DTOs, guards |
| `everything-claude-code:springboot-patterns` | Spring Boot layered architecture |
| `everything-claude-code:springboot-security` | Spring Security authn/authz |
| `everything-claude-code:springboot-verification` | Spring Boot verification loop |
| `everything-claude-code:nextjs-turbopack` | Next.js 16+ + Turbopack |
| `everything-claude-code:nuxt4-patterns` | Nuxt 4 hydration, performance, route rules |
| `everything-claude-code:frontend-patterns` | React, Next.js, state management |
| `everything-claude-code:bun-runtime` | Bun as runtime/pm/bundler/test runner |
| `everything-claude-code:jpa-patterns` | JPA/Hibernate entities, queries, transactions |
| `everything-claude-code:remotion-video-creation` | Remotion (video-in-React) rules |

## 9. Security

| Skill | Purpose |
|---|---|
| `security-review` | Complete security review of pending changes |
| `cso` | Chief Security Officer audit — secrets, infra-first |
| `everything-claude-code:security-review` | Auth, input, secrets, OWASP review |
| `everything-claude-code:security-scan` | Scan `.claude/` for config security issues |
| `everything-claude-code:security-bounty-hunter` | Hunt for bounty-worthy security issues |
| `everything-claude-code:perl-security` | Perl taint mode, safe exec |
| `everything-claude-code:defi-amm-security` | Solidity AMM, liquidity pool security |
| `everything-claude-code:evm-token-decimals` | Prevent silent EVM decimal mismatch |
| `everything-claude-code:nodejs-keccak256` | Prevent JS sha3-256 vs Keccak-256 confusion |
| `everything-claude-code:llm-trading-agent-security` | Autonomous trading agent wallet safety |
| `everything-claude-code:agent-payment-x402` | x402 payment execution for agents — budgets, controls |

## 10. Healthcare & compliance

| Skill | Purpose |
|---|---|
| `everything-claude-code:hipaa-compliance` | HIPAA privacy/security review |
| `everything-claude-code:healthcare-phi-compliance` | PHI/PII compliance |
| `everything-claude-code:healthcare-emr-patterns` | EMR/EHR clinical safety, encounters |
| `everything-claude-code:healthcare-cdss-patterns` | Clinical Decision Support patterns |
| `everything-claude-code:healthcare-eval-harness` | Patient safety eval harness |

## 11. Databases & data

| Skill | Purpose |
|---|---|
| `everything-claude-code:postgres-patterns` | Query optimization, schema, indexing |
| `everything-claude-code:clickhouse-io` | ClickHouse analytics queries |
| `everything-claude-code:database-migrations` | Schema migrations, rollbacks, zero downtime |

## 12. Deployment, ops, monitoring

| Skill | Purpose |
|---|---|
| `ship` | Ship workflow — detect base, test, review, bump VERSION |
| `land-and-deploy` | Merge PR, wait for CI/deploy, verify prod |
| `setup-deploy` | Configure `/land-and-deploy` platform |
| `canary` | Post-deploy canary monitoring |
| `everything-claude-code:canary-watch` | Monitor deployed URL for regressions |
| `everything-claude-code:deployment-patterns` | CI/CD, Docker, health checks |
| `everything-claude-code:docker-patterns` | Compose, container security, networking |
| `everything-claude-code:dashboard-builder` | Grafana/SigNoz dashboards from real questions |
| `document-release` | Post-ship docs update — diff + docs cross-ref |
| `benchmark` | Performance regression detection via browse daemon |
| `everything-claude-code:benchmark` | Performance baselines, regression detection |

## 13. Debugging, QA, live verification

| Skill | Purpose |
|---|---|
| `investigate` | Systematic debugging with root-cause phases |
| `qa` | QA test a web app and fix bugs found |
| `qa-only` | Report-only QA — structured findings, no fixes |
| `browse` | Fast headless browser for QA/dogfooding |
| `gstack` | Fast headless browser (alias) |
| `open-gstack-browser` | Launch GStack Browser — Chromium + sidebar |
| `setup-browser-cookies` | Import real-browser cookies into headless |
| `everything-claude-code:browser-qa` | Visual testing + UI interaction verification |
| `everything-claude-code:e2e-testing` | Playwright E2E, Page Object Model, CI/CD |
| `everything-claude-code:e2e` | Legacy shim for e2e-testing |
| `ui-demo` | Record polished UI demo videos via Playwright |

## 14. Design & UX

| Skill | Purpose |
|---|---|
| `design-consultation` | Product understanding + landscape research + direction |
| `design-shotgun` | Generate multiple AI design variants, comparison board |
| `design-html` | Design finalization — production Pretext-native HTML/CSS |
| `design-review` | Designer's-eye visual QA — inconsistency, hierarchy |
| `frontend-design:frontend-design` | Distinctive production-grade frontend design |
| `everything-claude-code:frontend-design` | Same as above in ECC namespace |
| `ui-ux-pro-max:ui-ux-pro-max` | UI/UX intelligence — 50+ styles, 161 palettes |
| `everything-claude-code:liquid-glass-design` | iOS 26 Liquid Glass material |
| `everything-claude-code:design-system` | Generate/audit design systems, visual consistency |
| `everything-claude-code:accessibility` | WCAG 2.2 AA design/implement/audit |
| `everything-claude-code:click-path-audit` | Trace every button through full state transitions |
| `everything-claude-code:frontend-slides` | Stunning HTML presentations, PPT conversion |

## 15. Content, marketing, outreach

| Skill | Purpose |
|---|---|
| `everything-claude-code:content-engine` | Platform-native content for X/LinkedIn/TikTok/YouTube |
| `everything-claude-code:crosspost` | Distribute content across X/LinkedIn/Threads/Bluesky |
| `everything-claude-code:brand-voice` | Source-derived writing style from real posts |
| `everything-claude-code:article-writing` | Long-form articles, guides, tutorials |
| `everything-claude-code:seo` | Technical SEO, on-page, structured data, Core Web Vitals |
| `everything-claude-code:investor-outreach` | Cold emails, warm intros, follow-ups |
| `everything-claude-code:investor-materials` | Pitch decks, one-pagers, investor memos |
| `everything-claude-code:lead-intelligence` | AI-native lead pipeline (Apollo/Clay/ZoomInfo replacement) |
| `everything-claude-code:market-research` | Market/competitive/due-diligence |
| `everything-claude-code:x-api` | X/Twitter API — post tweets, threads, DMs |
| `everything-claude-code:social-graph-ranker` | Weighted social-graph ranking for warm intros |
| `everything-claude-code:connections-optimizer` | Reorganize X/LinkedIn network, pruning |

## 16. Ops — email, messaging, knowledge, notifications

| Skill | Purpose |
|---|---|
| `everything-claude-code:email-ops` | Mailbox triage, draft, send-verify, follow-up |
| `everything-claude-code:messages-ops` | Live messaging workflow across platforms |
| `everything-claude-code:google-workspace-ops` | Drive/Docs/Sheets/Slides as one surface |
| `everything-claude-code:unified-notifications-ops` | GitHub/Linear/desktop as one surface |
| `everything-claude-code:knowledge-ops` | KB management, ingestion, sync, retrieval |
| `everything-claude-code:terminal-ops` | Evidence-first repo execution workflow |
| `everything-claude-code:automation-audit-ops` | Automation inventory and overlap audit |
| `everything-claude-code:research-ops` | Evidence-first current-state research |
| `everything-claude-code:project-flow-ops` | Triage GitHub + Linear issues/PRs |

## 17. Repo/issue operations

| Skill | Purpose |
|---|---|
| `everything-claude-code:github-ops` | Repo automation, issue triage, PR management |
| `everything-claude-code:jira` | Retrieve/update Jira tickets, status, comments |
| `everything-claude-code:jira-integration` | Same as above, for requirements analysis |
| `everything-claude-code:prp-pr` | Create GitHub PR from branch — discover templates |
| `everything-claude-code:prp-commit` | Quick commit with natural-language file targeting |
| `everything-claude-code:git-workflow` | Branching, commits, merge vs rebase |
| `everything-claude-code:repo-scan` | Cross-stack source code asset audit |
| `everything-claude-code:codebase-onboarding` | Generate structured onboarding guide |

## 18. Cleanup, health, retros, skill meta

| Skill | Purpose |
|---|---|
| `simplify` | Review changed code for reuse/quality/efficiency |
| `health` | Code quality dashboard — types/lint/tests |
| `retro` | Weekly engineering retrospective — commits + patterns |
| `fewer-permission-prompts` | Scan transcripts, allow common read-only tools |
| `everything-claude-code:plankton-code-quality` | Write-time format/lint/CLI quality |
| `everything-claude-code:skill-stocktake` | Audit skills and commands for quality |
| `everything-claude-code:skill-health` | Skill portfolio health dashboard |
| `everything-claude-code:skill-create` | Extract patterns from git history to SKILL.md |
| `everything-claude-code:skill-comply` | Visualize whether skills/rules are followed |
| `everything-claude-code:rules-distill` | Extract cross-skill principles into rules |

## 19. AI engineering, agents, evals

| Skill | Purpose |
|---|---|
| `claude-api` | Build/debug/optimize Claude API apps, prompt caching |
| `everything-claude-code:claude-api` | Claude API patterns for Python/TS |
| `everything-claude-code:mcp-server-patterns` | Build MCP servers with Node/TS SDK |
| `everything-claude-code:agentic-engineering` | Operate as eval-first agentic engineer |
| `everything-claude-code:agent-harness-construction` | Design agent action spaces, tools, observations |
| `everything-claude-code:agent-introspection-debugging` | Self-debug AI agent failures |
| `everything-claude-code:autonomous-loops` | Patterns for continuous autonomous CC loops |
| `everything-claude-code:continuous-agent-loop` | Patterns with quality gates + evals |
| `everything-claude-code:autonomous-agent-harness` | CC-as-autonomous-agent with persistent memory |
| `everything-claude-code:claude-devfleet` | Orchestrate multi-agent Claude DevFleet |
| `everything-claude-code:devfleet` | Legacy shim for claude-devfleet |
| `everything-claude-code:dmux-workflows` | Multi-agent via dmux (tmux pane manager) |
| `everything-claude-code:orchestrate` | Legacy shim for dmux-workflows + harness |
| `everything-claude-code:ralphinho-rfc-pipeline` | RFC-driven multi-agent DAG pipeline |
| `everything-claude-code:gan-style-harness` | GAN Generator-Evaluator harness |
| `everything-claude-code:santa-method` | Multi-agent adversarial verification |
| `everything-claude-code:santa-loop` | Adversarial dual-review convergence loop |
| `everything-claude-code:enterprise-agent-ops` | Long-lived agent workloads — observability, security |
| `everything-claude-code:eval` | Legacy shim for eval-harness |
| `everything-claude-code:eval-harness` | Formal evaluation framework for CC sessions |
| `everything-claude-code:learn-eval` | Extract patterns, self-evaluate, save |
| `everything-claude-code:continuous-learning` | Auto-extract reusable patterns from sessions |
| `everything-claude-code:continuous-learning-v2` | Instinct-based learning via hooks |
| `everything-claude-code:instinct-import` | Import instincts from file/URL |
| `everything-claude-code:instinct-export` | Export instincts from project/global scope |
| `everything-claude-code:instinct-status` | Show learned instincts and confidence |
| `everything-claude-code:promote` | Promote project-scoped instincts to global |
| `everything-claude-code:prune` | Delete pending instincts older than 30 days |
| `everything-claude-code:evolve` | Analyze instincts and suggest evolved structures |
| `everything-claude-code:ai-first-engineering` | Operating model for AI-majority eng teams |
| `everything-claude-code:iterative-retrieval` | Progressive context refinement for subagent context |
| `everything-claude-code:prompt-optimize` | Legacy shim for prompt-optimizer |
| `everything-claude-code:prompt-optimizer` | Analyze raw prompts, match ECC skills/commands |
| `everything-claude-code:team-builder` | Interactive agent picker for parallel teams |
| `everything-claude-code:agent-sort` | ECC-install plan for a specific repo |
| `everything-claude-code:agent-eval` | Head-to-head coding-agent comparison |
| `everything-claude-code:benchmark-models` | Cross-model benchmark for gstack skills |
| `everything-claude-code:cost-aware-llm-pipeline` | Model routing, caching, budget |

## 20. Hooks, keybindings, config, safety

| Skill | Purpose |
|---|---|
| `update-config` | Configure CC harness via `settings.json` |
| `keybindings-help` | Customize `~/.claude/keybindings.json` |
| `loop` | Run a prompt/command on a recurring interval |
| `careful` | Guardrails before destructive commands (`rm -rf`, etc.) |
| `freeze` | Restrict edits to a directory for the session |
| `unfreeze` | Clear the `/freeze` boundary |
| `guard` | Full safety — careful + freeze combined |
| `everything-claude-code:safety-guard` | Prevent destructive ops on production |
| `everything-claude-code:hookify` | Create hooks from conversation analysis |
| `everything-claude-code:hookify-help` | Help with the hookify system |
| `everything-claude-code:hookify-list` | List all configured hookify rules |
| `everything-claude-code:hookify-rules` | Create a hookify rule |
| `everything-claude-code:hookify-configure` | Enable/disable hookify rules |
| `everything-claude-code:configure-ecc` | Interactive ECC installer |
| `everything-claude-code:workspace-surface-audit` | Audit repo, MCP, plugins, env surfaces |

## 21. Research, search, docs, media

| Skill | Purpose |
|---|---|
| `everything-claude-code:search-first` | Research-before-coding — find existing tools |
| `everything-claude-code:docs` | Legacy shim for documentation-lookup |
| `everything-claude-code:documentation-lookup` | Up-to-date docs via Context7 MCP |
| `everything-claude-code:exa-search` | Neural web/code/company research via Exa MCP |
| `everything-claude-code:deep-research` | Multi-source research via Firecrawl + Exa |
| `everything-claude-code:nutrient-document-processing` | OCR, convert, redact, sign, fill PDFs |
| `everything-claude-code:videodb` | Ingest/analyze video + audio |
| `everything-claude-code:manim-video` | Reusable Manim technical explainers |
| `everything-claude-code:video-editing` | AI-assisted video editing workflows |
| `everything-claude-code:fal-ai-media` | fal.ai MCP — image/video/audio generation |
| `nano-banana` | Required for all image generation — Nano Banana |
| `everything-claude-code:visa-doc-translate` | Translate visa documents, bilingual PDF |

## 22. Open-source contribution pipeline

| Skill | Purpose |
|---|---|
| `everything-claude-code:opensource-pipeline` | Fork, sanitize, package for public release |

## 23. Architecture, decisions, patterns

| Skill | Purpose |
|---|---|
| `everything-claude-code:architecture-decision-records` | Capture decisions as structured ADRs |
| `everything-claude-code:hexagonal-architecture` | Ports & Adapters design, domain boundaries |
| `everything-claude-code:api-design` | REST naming, status codes, pagination |
| `everything-claude-code:backend-patterns` | Backend architecture, DB optimization |
| `everything-claude-code:regex-vs-llm-structured-text` | When regex vs LLM for parsing |
| `everything-claude-code:content-hash-cache-pattern` | SHA-256 content-hash caching |

## 24. DX, code tours, onboarding

| Skill | Purpose |
|---|---|
| `devex-review` | Live DX audit — uses browse to test developer UX |
| `everything-claude-code:code-tour` | Persona-targeted `.tour` walkthroughs |
| `everything-claude-code:product-capability` | Translate PRD into implementation-ready capability |
| `everything-claude-code:product-lens` | Validate "why" before building, product diagnostics |

## 25. Industry verticals & domain expertise

| Skill | Purpose |
|---|---|
| `everything-claude-code:inventory-demand-planning` | Demand forecasting, safety stock, replenishment |
| `everything-claude-code:production-scheduling` | Job sequencing, line balancing, changeovers |
| `everything-claude-code:quality-nonconformance` | QC, root cause, nonconformance investigation |
| `everything-claude-code:returns-reverse-logistics` | Returns, inspection, disposition, refurb |
| `everything-claude-code:logistics-exception-management` | Delays, damages, losses, claims |
| `everything-claude-code:carrier-relationship-management` | Carrier portfolios, rate negotiation |
| `everything-claude-code:customs-trade-compliance` | Tariff classification, duty optimization |
| `everything-claude-code:energy-procurement` | Electricity/gas procurement, tariffs, DR |
| `everything-claude-code:customer-billing-ops` | Subscriptions, refunds, churn triage |
| `everything-claude-code:finance-billing-ops` | Pricing, refunds, team-billing truth |
| `everything-claude-code:ecc-tools-cost-audit` | ECC tools burn and billing audit |

## 26. PyTorch, ML, specialty

| Skill | Purpose |
|---|---|
| `everything-claude-code:pytorch-patterns` | PyTorch deep-learning patterns |
| `everything-claude-code:foundation-models-on-device` | Apple FoundationModels — on-device LLM |

## 27. Miscellaneous

| Skill | Purpose |
|---|---|
| `everything-claude-code:aside` | Answer a quick side question without losing context |
| `everything-claude-code:projects` | List known projects and instinct statistics |
| `everything-claude-code:ck` | Persistent per-project memory for CC |
| `everything-claude-code:claw` | Legacy shim for nanoclaw-repl |
| `everything-claude-code:nanoclaw-repl` | Zero-dep session-aware REPL on CC |
| `everything-claude-code:api-connector-builder` | Build API connector matching repo integration |
| `everything-claude-code:data-scraper-agent` | Automated AI data collection for any public source |
| `everything-claude-code:openclaw-persona-forge` | Forge OpenClaw AI Agent personas |
| `superpowers:dispatching-parallel-agents` | Dispatch 2+ independent tasks in parallel |
| `superpowers:systematic-debugging` | Systematic debug discipline before proposing fixes |
| `superpowers:using-git-worktrees` | Isolate feature work in git worktrees |
| `superpowers:using-superpowers` | Meta — how to find and use skills |
| `superpowers:test-driven-development` | TDD for any feature or bugfix |
| `superpowers:writing-skills` | Create/edit/verify skills |
| `superpowers:execute-plan` | Deprecated — use executing-plans |
| `superpowers:write-plan` | Deprecated — use writing-plans |
| `superpowers:brainstorm` | Deprecated — use brainstorming |

---

## Summary by count

Approximate totals (some skills appear under multiple themes because they serve multiple purposes):

| Theme | Count |
|---|---|
| Language review + testing + build + patterns | ~60 |
| AI engineering, agents, evals, harnesses | ~30 |
| Planning, brainstorming, review (CEO/Eng/Design/DX) | ~20 |
| Framework patterns (Laravel, Django, Spring, Next, Nuxt…) | ~18 |
| Security + compliance + healthcare | ~15 |
| Hooks, keybindings, config, safety | ~13 |
| Design, UX, frontend | ~12 |
| Ops (email, messaging, GitHub, Google, notifications) | ~12 |
| Content, marketing, outreach, investor | ~12 |
| Research + docs + media | ~11 |
| Industry verticals | ~11 |
| Cleanup, health, retros, skill meta | ~10 |
| Debug, QA, live verification | ~9 |
| Deployment, ops, monitoring, canary | ~9 |
| Workflow, sessions, context | ~9 |
| Repo/issue/PR operations | ~8 |
| **Total unique skills listed** | **~210** |

---

## How to use this file

- Scan by theme when you're not sure which skill fits.
- When you know the slash name, just type `/skill-name`.
- Plugin-namespaced skills work with their full name (e.g. `superpowers:brainstorming`, `everything-claude-code:tdd`).
- Deprecated skills still work but will be removed — migrate to the listed replacement.
- For open-source contribution specifically: `opensource-contributor` (agent, not skill) + `repo-finder` (agent) + `merge-probability-scorer` (agent) live in `superhuman/agents/`, not in the skill namespace.
