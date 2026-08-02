/* =====================================================================
   Q5: Underwriting Standards Effectiveness Over Time
   Did the average risk profile of approved borrowers (DTI,
   verification, grade mix) shift over the years, did that shift
   correlate with better/worse outcomes, and what does that imply
   about policy changes?

   METHOD:
   - Risk profile (avg DTI, % not verified, % prime A/B, % subprime
     D/E/F/G) computed on ALL loans originated in each issue year —
     this describes who was APPROVED that year and doesn't depend on
     knowing the eventual outcome, so active loans are included here.
   - Outcome (PD) computed on TERMINAL loans only (Charged Off/Default
     + Fully Paid) per issue year — same censoring principle as
     Q2/Q3/Q4. Active loans' fates aren't known yet.
   - The two halves deliberately use different loan counts per year by
     design (total_originations vs terminal_loan_count) — NOT a bug.
     For recent years, terminal_loan_count is a small fraction of
     total_originations, meaning that year's pd_pct is an early,
     incomplete read, not a final number.
   ===================================================================== */

WITH yearly_profile AS (
    SELECT
        YEAR(f.issue_date) AS issue_year,
        AVG(b.dti) AS avg_dti,
        SUM(CASE WHEN b.verification_status = 'Not Verified'
            THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS pct_not_verified,
        SUM(CASE WHEN dg.grade IN ('A','B')
            THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS pct_prime_grade,
        SUM(CASE WHEN dg.grade IN ('D','E','F','G')
            THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS pct_subprime_grade,
        COUNT(*) AS total_originations
    FROM lc.fact_loan f
    JOIN lc.dim_borrower b ON f.borrower_key = b.borrower_key
    JOIN lc.dim_grade dg ON f.grade_key = dg.grade_key
    WHERE f.issue_date IS NOT NULL
    GROUP BY YEAR(f.issue_date)
),

yearly_outcome AS (
    SELECT
        YEAR(f.issue_date) AS issue_year,
        COUNT(*) AS terminal_loan_count,
        SUM(CASE WHEN f.loan_status IN (
            'Charged Off','Default',
            'Does not meet the credit policy. Status:Charged Off'
        ) THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS pd
    FROM lc.fact_loan f
    WHERE f.loan_status IN (
        'Charged Off','Default',
        'Does not meet the credit policy. Status:Charged Off',
        'Fully Paid','Does not meet the credit policy. Status:Fully Paid'
    )
    GROUP BY YEAR(f.issue_date)
)

SELECT
    p.issue_year,
    p.total_originations,
    CAST(ROUND(p.avg_dti, 2) AS DECIMAL(5,2)) AS avg_dti,
    CAST(ROUND(p.pct_not_verified * 100, 2) AS DECIMAL(5,2)) AS pct_not_verified,
    CAST(ROUND(p.pct_prime_grade * 100, 2) AS DECIMAL(5,2)) AS pct_prime_grade,
    CAST(ROUND(p.pct_subprime_grade * 100, 2) AS DECIMAL(5,2)) AS pct_subprime_grade,
    o.terminal_loan_count,
    CAST(ROUND(o.pd * 100, 2) AS DECIMAL(5,2)) AS pd_pct
FROM yearly_profile p
JOIN yearly_outcome o ON p.issue_year = o.issue_year
ORDER BY p.issue_year;

/* =====================================================================
   NARRATIVE CONCLUSION

   Read only the properly-matured years as trend evidence: 2009-2015
   are fully or near-fully matured (terminal_loan_count is 89%-100% of
   total_originations). 2016 (67% matured) is directional. 2017 (38%)
   and 2018 (11%) are too early to read as outcomes at all — their low
   pd_pct reflects incomplete maturation, not genuinely better credit
   performance. 2007-2008 are real but trivially small cohorts
   (603, 2,393 loans) from LC's pre-scale years — context, not trend.

   THE CORE FINDING: grade mix and realized outcomes moved in OPPOSITE
   directions. Subprime origination share fell from 47.4% (2007) to a
   low of ~22-26% through the 2012-2016 scale-up years — Lending Club
   was, on paper, approving a SAFER mix of borrowers by grade. Despite
   that, realized default rate on matured cohorts rose the entire
   time: from a trough of ~13.7%-14.0% (2009-2010) to ~18.5%-20.2%
   (2014-2015), continuing upward into the directional 2016 read
   (23.3%). A grade-mix-driven story would predict defaults falling
   alongside the falling subprime share — the opposite happened.

   WHAT EXPLAINS THE GAP: average DTI climbed almost continuously
   across the entire period, from single digits in 2007 to ~17-19.7%
   by 2013 onward, and never came back down. Borrowers got steadily
   more leveraged relative to income even as their letter grade
   composition looked more conservative — meaning DTI crept up faster
   than the grade system priced it in, or grade was capturing a
   different risk dimension than leverage. Either way, the grade
   distribution alone was a misleading signal of book-wide risk during
   this period; DTI trend told the truer story and outcomes confirm it.

   A SECOND WARNING SIGN, TOO RECENT TO CONFIRM IN OUTCOMES YET:
   pct_not_verified fell steadily from 2008 through a low of ~27%
   (2015) — verification tightened over the scale-up years, plausibly
   part of why the deterioration wasn't even worse. But it reversed
   in 2017 (35.8%) and 2018 (40.4%), the two years with by far the
   largest origination volume (443k and 495k loans) and the two years
   too censored to show a reliable outcome yet. Loosening verification
   at the same time volume roughly doubled is the combination most
   worth flagging to a credit-risk stakeholder — if this book performs
   like the DTI-driven deterioration of 2012-2016, it likely won't show
   up in the data until 2019-2020, well after this dataset ends.

   POLICY IMPLICATION: grade-mix targets are not a sufficient
   underwriting control on their own — DTI and verification standards
   need to be monitored and tightened independently of grade
   composition, since this book's experience shows grade improving
   while true credit risk (leverage) and data quality (verification)
   moved the other way, with realized defaults ultimately following
   DTI and verification, not grade mix.
   ===================================================================== */
