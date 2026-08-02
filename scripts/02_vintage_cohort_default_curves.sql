/* =====================================================================
   Q2: Vintage Cohort Default Curves
   Grouping loans by issue month/quarter, how does cumulative default
   rate change with loan age, and does it differ by origination period?

   METHOD: survival-style vintage curve using a calendar/MOB
   (months-on-book) spine, not a single row per loan.

   KEY ASSUMPTIONS (documented in README):
   - `last_credit_pull_d` is NOT in this dataset's trimmed columns, so
     `last_pymnt_d` is used for BOTH the snapshot anchor and the
     default-age proxy below. This is a weaker proxy than
     last_credit_pull_d — call this out explicitly in the README.
   - Snapshot date = MAX(last_pymnt_d) across the table, i.e. the
     data's effective "as of" date. Every loan's exposure is capped
     at min(months since issue_date at snapshot, loan term).
   - Default event = Charged Off / Default / "Does not meet credit
     policy. Status:Charged Off" ONLY. "Late (31-120 days)" is NOT
     treated as default — it's a non-terminal, still-active status
     and is folded into the censored/active population.
   - Default age proxy = DATEDIFF(MONTH, issue_date, last_pymnt_d + 120
     days) for defaulted loans. The +120 days corrects for LC's
     documented charge-off policy (loans are charged off ~120-150
     days past due, not at the last payment itself). Still an
     approximation — a fixed lag doesn't capture per-loan variation
     in exactly when charge-off happened. State this in the README.
   - Fully Paid loans are permanently non-default at every age from
     payoff onward — they stay in the denominator at every MOB up to
     their exposure cap, contributing 0 to the bad flag. This keeps
     the cohort denominator FIXED (no survivorship bias from dropping
     "ongoing"/paid loans).
   - Currently active loans (Current/Late/Grace) are only observable
     up to their current age — we do NOT project their future outcome,
     so they simply stop contributing rows past their exposure cap
     (correct censoring, not an exclusion of the loan).
   ===================================================================== */

WITH snapshot AS (
    -- Single global "as of" date for the whole dataset.
    -- Everything is aged relative to this, not to "today" (the data
    -- was pulled once, not live). last_pymnt_d is stored as text
    -- ('Dec-2015' style) so it's parsed to a real DATE before MAX().
    SELECT MAX(TRY_CONVERT(DATE, '01-' + last_pymnt_d, 106)) AS snapshot_date
    FROM lc.fact_loan
),

loan_base AS (
    SELECT
        f.loan_id,
        CONCAT(YEAR(f.issue_date), ' Q', DATEPART(QUARTER, f.issue_date)) AS cohort,

        -- Parse "36 months" / "60 months" text into an integer.
        TRY_CAST(LEFT(LTRIM(f.term), 2) AS INT) AS term_months,

        -- Is this loan a confirmed default? (terminal, bad)
        CASE
            WHEN f.loan_status IN (
                'Charged Off',
                'Default',
                'Does not meet the credit policy. Status:Charged Off'
            ) THEN 1 ELSE 0
        END AS is_default,

        -- Age (in months) at which the default became terminal.
        -- Only meaningful when is_default = 1. Proxy = last_pymnt_d +
        -- a fixed charge-off lag, since last_credit_pull_d isn't
        -- available. LC's documented policy charges off loans ~120-150
        -- days past due — 120 days used here as the standard round-
        -- number proxy. This is still an approximation; state it as one.
        -- last_pymnt_d is text ('Dec-2015') so it's parsed to DATE first.
        CASE
            WHEN f.loan_status IN (
                'Charged Off',
                'Default',
                'Does not meet the credit policy. Status:Charged Off'
            )
            THEN DATEDIFF(
                MONTH,
                f.issue_date,
                DATEADD(DAY, 120, TRY_CONVERT(DATE, '01-' + f.last_pymnt_d, 106))
            )
        END AS default_age_months,

        -- How many months of exposure do we actually get to observe
        -- for this loan? Capped by both the snapshot date and the
        -- loan's own term (no point tracking past maturity).
        CASE
            WHEN TRY_CAST(LEFT(LTRIM(f.term), 2) AS INT) IS NULL THEN NULL
            ELSE
                LEAST(
                    DATEDIFF(MONTH, f.issue_date, s.snapshot_date),
                    TRY_CAST(LEFT(LTRIM(f.term), 2) AS INT)
                )
        END AS exposure_cap_months

    FROM lc.fact_loan f
    CROSS JOIN snapshot s
    WHERE f.issue_date IS NOT NULL
),

tally AS (
    -- Calendar spine: 0..60 months on book (covers 36 and 60 month terms).
    -- Recursive CTE instead of a physical numbers table — swap for a
    -- real tally table if one exists in the schema already.
    SELECT 0 AS mob
    UNION ALL
    SELECT mob + 1 FROM tally WHERE mob < 60
),

loan_age_spine AS (
    -- Explode each loan into one row per month-on-book, from 0 up to
    -- its exposure cap. This is what makes the denominator fixed and
    -- correct — every loan contributes a row at every age it was
    -- actually observed for, whether it ever defaulted or not.
    SELECT
        lb.loan_id,
        lb.cohort,
        t.mob,
        CASE
            WHEN lb.is_default = 1 AND lb.default_age_months <= t.mob THEN 1
            ELSE 0
        END AS is_bad_by_this_age
    FROM loan_base lb
    INNER JOIN tally t
        ON t.mob <= lb.exposure_cap_months
    WHERE lb.exposure_cap_months IS NOT NULL
),

age_summary AS (
    SELECT
        cohort,
        mob AS loan_age_months,
        COUNT(*) AS total_loans_at_risk,
        SUM(is_bad_by_this_age) AS cumulative_defaults
    FROM loan_age_spine
    GROUP BY cohort, mob
)

SELECT
    cohort,
    loan_age_months,
    total_loans_at_risk,
    cumulative_defaults,
    -- Numeric, not string — so it's chartable downstream in BI/Python.
    CAST(
        ROUND(100.0 * cumulative_defaults / NULLIF(total_loans_at_risk, 0), 2)
        AS DECIMAL(5, 2)
    ) AS cumulative_default_rate_pct
FROM age_summary
ORDER BY cohort, loan_age_months;

/* =====================================================================
   FINDINGS (from query output, terminal/MOB-36 rates unless noted)
 
   - Highest default rates are in the earliest vintages: 2007 Q4 (28.0%)
     and 2008 Q1 (22.4%) are the worst-performing cohorts in the dataset.
     2007 Q2/Q3 show even wider swings (12.5%, 21.1%) but on tiny cohorts
     (n=24, n=190) — noise, not signal, don't lead with these.
   - Rates fall sharply and bottom out around 2010-2011 vintages
     (~10.5%-13.8%), the best-performing origination period on record.
   - Rates climb steadily again from 2012 through 2016, reaching
     16.5%-16.8% for 2015 Q1-2016 Q1 — approaching (but not matching)
     the 2007-2008 peak. This is a ~6pp deterioration in credit quality
     over that growth period, and the headline finding for this question.
   - 2017-2018 vintages can't be judged on terminal rate yet — they're
     still censored (capped at MOB 5-26 depending on quarter) because
     the dataset's snapshot doesn't reach their full term. Comparing
     them to fully-matured cohorts at the same age (not at MOB 36)
     is the only fair comparison until more data ages in.
   - Origination period clearly matters: default rate is not flat
     across cohorts, and moves with macro/credit-cycle timing rather
     than randomly — answers the "does it differ" half of the question.
   ===================================================================== */
