#!/usr/bin/env bash
# Loads the schema, then the seed data (sample by default; the full dataset
# only when USE_FULL_DATASET=true).
#
# NOT run directly by Postgres: db/init/00-init.sql (the only file in the init
# folder) calls it with `bash`, so it does not depend on the file's executable
# bit, its #! line, or its line endings (CRLF is stripped first). That made
# first-start failures on some students' machines ("bad interpreter:
# Permission denied", "pipefail\r") impossible.
set -euo pipefail

on_error() {
  echo "" >&2
  echo "[init] !!! DATABASE SETUP FAILED (line $1) !!!" >&2
  echo "[init] The data volume now holds a half-initialised database." >&2
  echo "[init] Fix: run   docker compose down -v   then   docker compose up -d" >&2
  echo "[init] (down -v deletes the volume so setup runs again from scratch)" >&2
}
trap 'on_error $LINENO' ERR

SCHEMA_DIR="/db"
SEED_FULL="$SCHEMA_DIR/seed/full"
SEED_SAMPLE="$SCHEMA_DIR/seed/sample"

echo "[init] applying schema..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$SCHEMA_DIR/schema.sql"

# Sample data is the DEFAULT: ~700 orders, loads in seconds, and is what the
# autograder and fixtures use. The real ~100k-order dataset is opt-in:
# set USE_FULL_DATASET=true in .env AND have db/seed/full/ populated.
if [ "${USE_FULL_DATASET:-}" = "true" ] && [ -d "$SEED_FULL" ] && [ -n "$(ls -A "$SEED_FULL" 2>/dev/null)" ]; then
  SEED_DIR="$SEED_FULL"
  echo "[init] USE_FULL_DATASET=true -- loading FULL Olist dataset from $SEED_DIR (this can take a few minutes)"
else
  SEED_DIR="$SEED_SAMPLE"
  echo "[init] loading sample dataset from $SEED_DIR"
fi

# Load order matters: parents before children (FK dependencies).
LOAD_ORDER=(
  product_category_name_translation
  sellers
  products
  customers
  geolocation
  orders
  order_items
  order_payments
  order_reviews
)

for table in "${LOAD_ORDER[@]}"; do
  file="$SEED_DIR/${table}.csv"
  if [ ! -f "$file" ]; then
    echo "[init]   WARNING: $file not found, skipping $table"
    continue
  fi

  if [ "$table" = "products" ]; then
    # The real Olist dataset has a known gap: a handful of categories show
    # up on products but were never added to the category-translation
    # lookup table (e.g. "pc_gamer"). Load into a staging table first (no
    # FK enforced there), backfill any missing category with a placeholder
    # translation, then insert for real -- so the FK stays meaningful
    # instead of just being dropped to work around messy real data.
    echo "[init]   loading products (backfilling any categories missing from the translation table first)"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" << SQL
CREATE TEMP TABLE products_staging (LIKE products INCLUDING ALL);
\copy products_staging FROM '$file' WITH (FORMAT csv, HEADER true, NULL '')

INSERT INTO product_category_name_translation (product_category_name, product_category_name_english)
SELECT DISTINCT product_category_name, product_category_name
FROM products_staging
WHERE product_category_name IS NOT NULL
ON CONFLICT (product_category_name) DO NOTHING;

INSERT INTO products SELECT * FROM products_staging;
SQL
  elif [ "$table" = "order_reviews" ]; then
    # Another known real-data quirk: order_reviews.csv has a handful of
    # duplicate review_id rows (looks like a re-survey/export artifact from
    # Olist's own pipeline). review_id is our primary key, so load into a
    # staging table WITHOUT that constraint (duplicates can land there),
    # then keep one row per review_id -- the most recently created, on the
    # reasonable assumption a later copy reflects a more complete review.
    echo "[init]   loading order_reviews (de-duplicating repeated review_ids first)"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" << SQL
CREATE TEMP TABLE order_reviews_staging (LIKE order_reviews INCLUDING DEFAULTS);
\copy order_reviews_staging FROM '$file' WITH (FORMAT csv, HEADER true, NULL '')

INSERT INTO order_reviews
SELECT DISTINCT ON (review_id) *
FROM order_reviews_staging
ORDER BY review_id, review_creation_date DESC NULLS LAST, review_answer_timestamp DESC NULLS LAST;
SQL
  else
    echo "[init]   loading $table"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
      -c "\copy $table FROM '$file' WITH (FORMAT csv, HEADER true, NULL '')"
  fi
done

echo "[init] done."
