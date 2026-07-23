-- ============================================================================
-- Business Question 1: Grade-vs-Pricing Mismatch
-- Does the interest rate charged by grade match the realized default rate?
-- ============================================================================
--
-- Author's design decisions:
-- 1. "Late (31-120 days)" is classified as a Bad Loan alongside Charged Off
--    and Default, since a loan this severely delinquent is functionally
--    close to a confirmed default, not a healthy/ongoing loan.
-- 2. Loans still in progress (Current, Issued, Grace Period, Late 16-30 days)
--    are excluded entirely from the default rate calculation. Counting them
--    as "not defaulted" would understate the true default rate, since their
--    final outcome isn't known yet.
-- 3. Default rate is calculated only among loans with a resolved outcome
--    (Bad Loan or Good Loan) — this is the denominator that gives a fair,
--    unbiased default rate.
-- ============================================================================

-- Step 1: Label every loan as Bad Loan / Good Loan / Ongoing, and attach
-- its grade so the labels can be aggregated by grade later.
WITH flagged_loan AS (
    SELECT
        dg.grade        AS grade,
        fl.loan_id       AS loan_id,
        fl.loan_status   AS loan_status,
        fl.int_rate      AS int_rate,
        CASE
            WHEN loan_status IN (
                'Charged Off',
                'Default',
                'Does not meet the credit policy. Status:Charged Off',
                'Late (31-120 days)'
            ) THEN 'Bad Loan'

            WHEN loan_status IN (
                'Fully Paid',
                'Does not meet the credit policy. Status:Fully Paid'
            ) THEN 'Good Loan'

            ELSE 'Ongoing'
        END AS loan_category
    FROM lc.fact_loan fl
    JOIN lc.dim_grade dg
        ON fl.grade_key = dg.grade_key
)

-- Step 2: Aggregate by grade — total loans, defaulted loans, average
-- interest rate, and default rate (%), excluding loans with no final
-- outcome yet.
SELECT
    grade,
    COUNT(*) AS total_loan,

    SUM(CASE WHEN loan_category = 'Bad Loan' THEN 1 ELSE 0 END) AS default_cnt,

    CONCAT(
        CAST(ROUND(AVG(int_rate), 2) AS DECIMAL(10,2)),
        ' %'
    ) AS avg_int_rate,

    CONCAT(
        CAST(
            ROUND(
                CAST(SUM(CASE WHEN loan_category = 'Bad Loan' THEN 1 ELSE 0 END) AS DECIMAL(10,2))
                / COUNT(*) * 100,
            2)
        AS DECIMAL(10,2)),
        ' %'
    ) AS default_rate_pct

FROM flagged_loan
WHERE loan_category != 'Ongoing'   -- exclude loans with no resolved outcome yet
GROUP BY grade
ORDER BY grade;

-- ============================================================================
-- Finding:
-- Interest rate rises roughly linearly with grade (A: 7.11% -> G: 27.61%),
-- but default rate rises disproportionately faster (A: 6.57% -> G: 50.91%).
-- Sharpest mispricing signal is the B->C transition: interest rate rises
-- only 3.35 points, while default rate jumps 9.51 points -- nearly 3x the
-- rate compensation for the actual increase in risk.
-- Grade G shows a 50.91% default rate against only a 27.61% rate premium,
-- raising the question of whether pricing adequately compensates for
-- expected loss once principal loss is factored in (tested directly in
-- the expected loss simulation, PD x LGD x EAD).
-- ============================================================================
