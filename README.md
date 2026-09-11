# rlm-skills

Claude Code skills for Salesforce Revenue Cloud (RLM) development.

Covers the full quote-to-cash lifecycle across 13 domain skills: product discovery, configuration, pricing, rate management, transaction management, approvals, fulfillment, usage management, billing, asset lifecycle, deployment, Agentforce integration, and a shared error reference.

---

## Skills

| Skill | Domain |
|---|---|
| `rlm-agentforce` | Agentforce agent authoring, GenAiFunction/GenAiPlugin patterns, session management |
| `rlm-assets` | Asset lifecycle — amendment, renewal, cancellation, co-term, delta pricing |
| `rlm-advanced-approvals` | Approval submission, work items, override, recall |
| `rlm-billing` | Billing schedules, invoices, credit memos, payments, tax engine wiring |
| `rlm-deployment` | GUID strategy, deployment sequences, post-deploy verification |
| `rlm-dynamic-revenue-orchestrator` | Fulfillment plans, callout providers, platform events |
| `rlm-pricing` | Price books, adjustments, attribute-based pricing, headless pricing API |
| `rlm-product-catalog` | Product classification, attributes, selling models, bundles |
| `rlm-product-configurator` | PST API, QuoteLineItemAttribute, BOM rules, two-step sequencing |
| `rlm-product-discovery` | `/connect/cpq/` endpoints, guided selection, qualification |
| `rlm-rate-management` | Rate cards, rate adjustments, binding objects, tiered rates |
| `rlm-transaction-management` | Quote/order creation, asset lifecycle actions, platform events |
| `rlm-usage-management` | Usage grants, entitlement buckets, drawdown, overage policies |

See [skills/WORKFLOW_GUIDE.md](skills/WORKFLOW_GUIDE.md) for the end-to-end quote-to-cash flow with skill boundaries at every step.

---

## Installation

```bash
git clone https://github.com/lzdravkov/rlm-skills.git
cd rlm-skills
./install.sh
```

This copies all skills into `~/.claude/skills/`, making them available in every Claude Code project.

### Updating

```bash
git pull
./install.sh
```

`install.sh` overwrites existing skill files on each run — no cleanup needed.

### Project-local install (optional)

To install into a specific project instead of globally:

```bash
./install.sh /path/to/your/project/.claude/skills
```

---

## Structure

```
skills/
  WORKFLOW_GUIDE.md              ← end-to-end quote-to-cash flow diagram
  shared/
    error-reference.md           ← cross-cutting error catalog (30+ errors)
  rlm-<domain>/
    SKILL.md                     ← skill definition (frontmatter + instructions)
    references/                  ← exhaustive field/API reference files
    scripts/                     ← reusable Apex templates (where applicable)
```

Each `SKILL.md` follows a three-level progressive disclosure pattern:
- **SKILL.md** — when to use, step-by-step instructions, common issues, see also
- **references/** — full field-level reference, API request/response bodies
- **scripts/** — copy-paste-ready Apex templates

---

## API Version

All skills target **Salesforce Revenue Cloud (Revenue Management) API v68.0 (Winter '27)**.

---

## Contributing

1. Edit the relevant `SKILL.md` or reference file
2. Bump the `version` in frontmatter
3. Add a row to the `## Changelog` section
4. Run `./install.sh` to update your local Claude installation
5. Open a PR
