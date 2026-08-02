"""
trim_columns.py

Trims the Lending Club "accepted loans" CSV down to the 31 columns
needed for this project's star schema (fact_loan + dim_grade,
dim_borrower, dim_geography), ahead of loading into SQL Server via
BULK INSERT.

Input is expected to already be free of malformed/footer rows (i.e.
run this after any row-level cleaning) — this script only performs
column selection, streamed row by row to keep memory usage flat
regardless of file size.
"""

import csv

INPUT_PATH = r"C:\Users\Muhammad Faizan\accepted_2007_to_2018q4.csv\accepted_clean2.csv"
OUTPUT_PATH = r"C:\Users\Muhammad Faizan\accepted_2007_to_2018q4.csv\accepted_final.csv"

# The 31 columns needed downstream — everything else in the raw file
# is dropped.
NEEDED_COLUMNS = [
    "id", "loan_amnt", "funded_amnt", "term", "int_rate", "installment",
    "grade", "sub_grade", "emp_length", "home_ownership", "annual_inc",
    "verification_status", "issue_d", "loan_status", "zip_code", "addr_state",
    "dti", "delinq_2yrs", "fico_range_low", "fico_range_high", "open_acc",
    "pub_rec", "revol_util", "out_prncp", "total_pymnt", "total_rec_prncp",
    "total_rec_int", "recoveries", "collection_recovery_fee", "last_pymnt_d",
    "last_pymnt_amnt",
]


def trim_columns(input_path: str, output_path: str) -> None:
    """Stream the source CSV row by row, writing out only the needed
    columns. Streaming avoids loading the full multi-GB file into
    memory at once."""
    with open(input_path, "r", encoding="utf-8") as infile:
        reader = csv.DictReader(infile)

        with open(output_path, "w", newline="", encoding="utf-8") as outfile:
            writer = csv.DictWriter(outfile, fieldnames=NEEDED_COLUMNS)
            writer.writeheader()

            row_count = 0
            for row in reader:
                writer.writerow({col: row[col] for col in NEEDED_COLUMNS})
                row_count += 1

    print(f"Done — wrote {row_count:,} rows, {len(NEEDED_COLUMNS)} columns")


if __name__ == "__main__":
    trim_columns(INPUT_PATH, OUTPUT_PATH)
