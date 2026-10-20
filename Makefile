.PHONY: up down reset logs test capture sample

up:
	docker compose up -d
	@echo "Dashboard:  http://localhost:$${FRONTEND_PORT:-58080}"
	@echo "API:        http://localhost:$${BACKEND_PORT:-58000}"

down:
	docker compose down

reset:
	./scripts/reset_db.sh

logs:
	docker compose logs -f backend

test:
	docker compose --profile tools run --rm grading sh -c "cd backend && npm install --silent && cd ../grading && npm install --silent && node run_tests.js"

capture:
	docker compose --profile tools run --rm grading sh -c "cd backend && npm install --silent && cd ../grading && npm install --silent && node capture_fixtures.js $(FILTER)"

# Lecturer only: rebuild db/seed/sample/ as a subset of db/seed/full/, then run
# `make capture` to refresh the grading fixtures.
sample:
	python3 db/seed/make_sample_from_full.py
