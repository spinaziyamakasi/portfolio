-- Runs automatically ONCE, on first start of an empty database volume
-- (Postgres docker-entrypoint-initdb.d convention).
--
-- Deliberately a .sql file that calls bash by name instead of a .sh file:
-- Postgres executes .sh files directly, which fails on some machines when the
-- file lacks the executable bit or has Windows (CRLF) line endings. Here the
-- script text is piped through `tr -d '\r'` first, so neither can break it.
-- This file itself may also be checked out with CRLF; the trailing `#` comment on
-- the \! line makes a stray CR harmless.
\echo [init] starting database setup
\! tr -d '\r' < /db/load_seed.sh > /tmp/load_seed.sh && bash /tmp/load_seed.sh # end of command (this comment swallows a stray CR if this file has Windows line endings)
\if :SHELL_ERROR
  \echo [init] !!! load_seed.sh failed -- see the messages above. Fix: docker compose down -v, then docker compose up -d
  SELECT 1/0 AS database_setup_failed;
\endif
