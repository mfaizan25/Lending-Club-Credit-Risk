# 💳 Lending Club Credit Risk Analysis

This portfolio project analyzes more than **2.26 million Lending Club loans (2007–2018)** using **SQL Server**. It demonstrates how a dimensional data warehouse and analytical SQL can be used to evaluate portfolio performance, identify credit risk trends, and support business decision-making.

## 🎯 Why This Project

Most public analyses of the Lending Club dataset stop at "train a
classifier to predict default." That's a data science exercise, not a
credit risk one.

This project asks a different question: if I would be the analyst
inside a bank holding this loan portfolio, what would I actually
need to report to leadership?

Not "will this loan default" — but *is our pricing right, how much
will we lose, where are we exposed, and did our own policy decisions
work.* That's the difference between a model and a risk function, and
it's the gap this project is built to close.

---

## 📊 Deliverables

| # | Question | Highlights |
|---|---|---|
| 0 | **Executive Portfolio Overview** — total exposure, funded amount, avg rate/DTI/income, grade & state distribution | Single-glance portfolio snapshot |
| 1 | **Grade-vs-Pricing Mismatch** — does interest rate charged match realized default rate by grade? | Checks whether pricing keeps pace with actual risk |
| 2 | **Vintage Cohort Default Curves** — cumulative default rate by loan age, across origination periods | Calendar/months-on-book spine with proper censoring — no survivorship bias |
| 3 | **Expected Loss Simulation** — PD × LGD × EAD by segment, rolled up to portfolio EL | ~17% of live exposure is expected to be lost; risk concentrated in mid-tier grades, not the riskiest ones |
| 4 | **Geographic Concentration Risk** — which states carry the highest exposure *and* higher default rates | NY and FL flagged as genuine concentration risk |
| 5 | **Underwriting Standards Over Time** — did borrower risk profile shift, and how did outcomes respond | Grade mix improved, but rising DTI drove defaults up anyway |

---

## 🏗️ Data & Pipeline

- **Source:** Lending Club accepted loans, 2007–2018 (Kaggle mirror,
  `wordsforthewise/lending-club`)
- **Pipeline:** raw CSV → Python column trim (`trim_columns.py`, 150+
  columns → 31 needed) → SQL Server staging table → star schema
- **Warehouse:** SQL Server, star schema — `fact_loan` (2.26M rows)
  joined to `dim_grade` (35 sub-grades), `dim_borrower` (2.26M, 1:1
  with loans), `dim_geography` (3,423 state/zip combinations)

See the [Pipeline Diagram](./Docs/pipeline_diagram.png) and [Entity Relationship Diagram (ERD)](./Docs/schema_erd.png) for a visual overview of the data pipeline and warehouse design.

---

## 🧱 Data Quality & Engineering Challenges

Public datasets don't arrive analysis-ready — documenting what had to
be worked around is part of this project's value, not something to
hide:

- **No explicit charge-off date.** The cleaned dataset has no
  `last_credit_pull_d`, so default timing (Q2, Q3) is proxied as
  `last_pymnt_d + 120 days`, matching Lending Club's documented
  charge-off policy — stated as an approximation everywhere it's used.
- **Text-formatted dates.** `issue_d` and `last_pymnt_d` arrive as
  `'Dec-2015'` style strings, not real dates — every date calculation
  parses them explicitly rather than assuming a typed column.
- **Survivorship bias is easy to introduce by accident.** An early
  draft of the vintage cohort query (Q2) excluded active/paid-off
  loans from the denominator, inflating default rates and breaking
  cross-cohort comparisons. Fixed with a calendar/months-on-book spine
  so cohort size stays fixed and loans are properly censored instead
  of dropped.
- **Surrogate keys hide their own grain.** `grade_key` is keyed at
  sub-grade level (A1–G5), not letter grade — grouping by the key
  before joining to `dim_grade` silently returns 5 rows per letter
  grade instead of 1. Every query joins to the dimension *before*
  aggregating.
- **Small-sample states and cohorts.** Some states (e.g. Iowa, 14
  terminal loans) and early vintages (2007 Q2–Q3, a few hundred loans)
  are too thin to support a reliable rate — flagged explicitly in
  findings rather than ranked alongside full-sized segments.
- **One row excluded, on purpose.** A single loan (id `96387212`) has
  a NULL zip code and is excluded from the star schema rather than
  patched with an assumed value — a documented tradeoff, not a bug.

---

## 🔍 Key Findings

**Grade-driven risk (Q1, Q3):** Default rate climbs monotonically by
grade, 6% (A) up to ~50% (G) — a clean, reliable signal. But dollar
losses don't follow the same pattern: mid-tier grades (B/C) carry the
largest share of exposure, so they — not the highest-PD grades —
drive the biggest chunk of the portfolio's expected loss.

**Vintage performance (Q2):** Default rates bottomed out for 2010–2011
originations (~10–15% terminal rate) and climbed steadily through the
2012–2016 growth years, approaching 2007–2008 crisis-era levels by
2015–2016 vintages.

**Geographic concentration (Q4):** CA and TX are the two largest
exposure states but perform in line with or better than the portfolio
average. NY and FL combine large exposure *and* above-average default
rates — the clearest concentration risk in the book.

**Underwriting drift (Q5):** A progressively safer *grade mix* was
approved over time (less subprime), yet realized default rates rose
anyway — average borrower DTI crept up almost every year, outpacing
what grade alone priced in. Verification also loosened again in
2017–2018, a signal too recent to confirm in outcomes within this
dataset's window.

---


## 🛠️ Tech

SQL Server · T-SQL (CTEs, recursive CTEs, window functions) · Python
(pandas/csv) · star schema design · draw.io (Diagrams) 

---

## ⚠️ Known Limitations

- No `last_credit_pull_d` in the cleaned dataset — default timing is
  proxied as `last_pymnt_d + 120 days`, per Lending Club's documented
  charge-off policy. Approximate, not exact.
- 2016–2018 vintage/outcome reads are censored (loans haven't fully
  matured) — treated as directional, not final, throughout.
- One loan (id `96387212`) excluded from the star schema due to a
  NULL zip code — documented rather than patched.

---

---

## 👨‍💻 About the Author

### Muhammad Faizan

I'm **Credit Risk Analyst** & **Financial Data Analyst**
currently pursuing a **BSc (Hons) in Applied Management** at **BPP
University London** (Graduation: **2028**).

I enjoy building data-driven projects that combine **finance, SQL,
data warehousing, and business analytics** to solve real-world
business problems. My portfolio focuses on developing practical
analytical solutions that mirror the work performed in banking and
financial services.

### Areas of Interest

- Data Analysis
- Credit Risk Analytics
- Financial Data Analytics
- FP&A (Financial Planning & Analysis)
- Banking Analytics
- Business Intelligence
- SQL & Data Warehousing

### Connect with Me

- **GitHub:** [github.com/mfaizan25](https://github.com/mfaizan25)
- **LinkedIn:** [linkedin.com/in/mfaizan25](https://www.linkedin.com/in/mfaizan25/)
- **LeetCode:** [leetcode.com/u/mfaizan252](https://leetcode.com/u/mfaizan252/)

If you have feedback, suggestions, or would like to discuss data
analytics, finance, or potential opportunities, feel free to connect
with me.

---
