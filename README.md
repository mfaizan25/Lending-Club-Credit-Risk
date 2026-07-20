# 📊 Lending Club Credit Risk Analysis
SQL-only credit risk analysis on 2.26M Lending Club loans (2007-2018) — pricing mismatch, vintage cohort analysis, expected loss simulation, geographic concentration, and underwriting effectiveness. Built for FP&amp;A/credit risk analyst roles.

![SQL Server](https://img.shields.io/badge/SQL_Server-CC2927?style=flat&logo=microsoft-sql-server&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat&logo=python&logoColor=white)
![Status](https://img.shields.io/badge/Status-In_Progress-yellow)
![License](https://img.shields.io/badge/License-MIT-blue)

A SQL-only credit risk and portfolio analytics project built on **2.26 million real Lending Club loans (2007–2018)**, structured around the questions a bank's credit risk, FP&A, or portfolio management function actually asks — pricing validation, loss forecasting, concentration risk, and underwriting effectiveness. No predictive model. No black box. Just SQL, applied the way a risk analyst applies it.

**Core skills demonstrated:** SQL Server · T-SQL · Star Schema Design · ETL Pipeline Development · Window Functions · CTEs · Credit Risk Analysis · Expected Loss Modeling (PD × LGD × EAD) · Vintage/Cohort Analysis · Data Cleaning · Python

---

## Table of Contents
- [Why This Project](#why-this-project)
- [Headline Finding](#headline-finding)
- [Business Questions](#business-questions)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Data Source](#data-source)
- [Data Quality & Engineering Challenges](#data-quality--engineering-challenges)
- [Tech Stack](#tech-stack)
- [Author](#author)

---

## Why This Project

Most public analyses of the Lending Club dataset stop at "train a classifier to predict default." That's a data science exercise, not a credit risk one.

This project asks a different question: **if you were the analyst inside a bank holding this loan portfolio, what would you actually need to report to leadership?**

Not "will this loan default" — but *is our pricing right, how much will we lose, where are we exposed, and did our own policy decisions work.* That's the difference between a model and a risk function, and it's the gap this project is built to close.

---

## Headline Finding

> **Loan pricing does not scale proportionally with realized default risk.**

| Grade | Avg. Interest Rate | Default Rate | Loans |
|:-----:|:-------------------:|:--------------:|:--------:|
| A | 7.11% | 6.57% | 236,515 |
| B | 10.68% | 14.44% | 397,890 |
| C | 14.03% | 23.95% | 389,876 |
| D | 17.74% | 31.99% | 206,418 |
| E | 21.16% | 39.82% | 96,358 |
| F | 24.93% | 46.21% | 32,946 |
| G | 27.61% | 50.91% | 9,562 |

Interest rate climbs in roughly even steps across grades. Default rate does not.

**The sharpest signal sits at B→C:** rate rises just 3.3 points, but default rate jumps 9.5 points — nearly **3x** the compensation the pricing model applied for the actual increase in risk.

**The largest exposure sits at grade G:** over half of all loans default (50.9%). A 27.6% rate premium is unlikely to fully offset a loss rate that high once principal loss — not just foregone interest — is factored in. This is tested arithmetically in the expected loss simulation (`sql/09_expected_loss_simulation.sql`), not left as a visual observation.

---

## Business Questions

| # | Question | Maps to (real bank function) | Status |
|---|----------|-------------------------------|:------:|
| 1 | Does loan pricing reflect realized default risk? | Model validation / pricing governance | ✅ Done |
| 2 | How does default risk evolve by loan age and origination period? | Vintage analysis, stress testing | 🔄 In progress |
| 3 | What is the portfolio's total expected loss? | Loss provisioning (IFRS 9 / CECL-style) | ⏳ Planned |
| 4 | Where is the portfolio concentrated, and is it risky? | Concentration / correlated risk management | ⏳ Planned |
| 5 | Did underwriting standards change over time — did it work? | Policy effectiveness & governance | ⏳ Planned |

Each question is answered in its own `.sql` file under `/sql`, with the finding and business interpretation documented inline as comments — not just the query, the *reasoning*.

---

## Architecture

**Star schema, SQL Server:**
┌─────────────────┐
                │   dim_grade      │
                │  (35 rows)       │
                └────────┬─────────┘
                         │┌──────────────────┐    ┌────▼─────────────┐    ┌──────────────────┐
│  dim_borrower     │────│   fact_loan       │────│  dim_geography    │
│  (2.26M rows,     │    │  (2,260,667 rows) │    │  (3,423 rows)     │
│   1:1 w/ loan)    │    └───────────────────┘    └──────────────────┘
└───────────────────┘
Full ER diagram: `docs/schema_diagram.png`

**Design decision — `dim_borrower` is loan-level, not deduplicated.** With 11 continuous borrower attributes (income, DTI, FICO, etc.), attempting to deduplicate into a shared dimension caused join multiplication during development — a real bug caught, diagnosed, and fixed mid-build. Documented transparently in `docs/data_quality_notes.md` rather than hidden.

---

## Repository Structure
lending-club-credit-risk/
├── README.md
├── .gitignore
├── sql/
│   ├── 01_schema_creation.sql
│   ├── 02_staging_load.sql
│   ├── 03_dimension_population.sql
│   ├── 04_fact_load.sql
│   ├── 05_indexes.sql
│   ├── 06_eda_queries.sql
│   ├── 07_grade_pricing_mismatch.sql
│   ├── 08_vintage_cohort_analysis.sql
│   ├── 09_expected_loss_simulation.sql
│   ├── 10_geo_concentration_risk.sql
│   └── 11_underwriting_standards.sql
├── docs/
│   ├── schema_diagram.png
│   ├── data_dictionary.md
│   ├── data_quality_notes.md
│   └── eda_summary.md
└── data/
└── source_note.md
---

## Data Source

[LendingClub Loan Data](https://www.kaggle.com/datasets/wordsforthewise/lending-club) — Kaggle, `wordsforthewise/lending-club` mirror. Accepted loans, 2007–2018, ~2.26M rows, 151 raw columns (31 retained; selection rationale in `docs/data_dictionary.md`).

Raw data is **not committed** to this repo (1.6GB+). Reproduction steps via Kaggle API in `data/source_note.md`.

---

## Data Quality & Engineering Challenges

Real data problems hit and resolved during the ETL build — full detail in `docs/data_quality_notes.md`:

- **Embedded non-data rows** — summary/total lines mixed into the source CSV, filtered via Python regex validation against the loan ID field
- **Type mismatches** — decimal-formatted integers (`"0.0"`) breaking strict `INT` typing, resolved via staging-layer type widening
- **Join multiplication bug** — an over-deduplicated borrower dimension caused fact table row explosion; redesigned as loan-level to fix
- **One excluded row** — 1 of 2,260,668 loans dropped due to a missing geography field, explicitly documented rather than silently lost

---

## Tech Stack

`SQL Server` · `T-SQL` · `Python` (data cleaning) · `SSMS` · `Kaggle API` · `draw.io` (ER diagram)

---

## Author

**Muhammad Faizan**

BSc (Hons) Applied Management — BPP University London (graduating 2028)
London, UK

Currently building a portfolio of SQL/data analytics projects targeting **FP&A Analyst** and **Finance Data Analyst** roles at London financial institutions, with a focus on Summer 2027 internship applications. This project reflects that focus directly — every business question here maps to a real function inside a bank's credit risk or FP&A team, not a generic data science exercise.

**Other work:**
- [SQL Data Warehouse Project](https://github.com/mfaizan25/SQL-Datawarehouse-Project) — Bronze/Silver/Gold medallion architecture, stored procedures, MERGE operations

**Connect:**
[LinkedIn](https://www.linkedin.com/in/mfaizan25/) · [mfaizan2570@gmail.com](mailto:mfaizan2570@gmail.com)

---

*Open to feedback on this project — if you spot something worth improving in the schema design or analysis, an issue or PR is welcome.*
