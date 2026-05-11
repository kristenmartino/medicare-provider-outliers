# Common dev commands. Run from project root.
.PHONY: help install debug build test docs serve publish-docs clean

VENV_PY := .venv/bin/python
DBT := .venv/bin/dbt

help:  ## Show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

install:  ## Set up venv + install dbt-snowflake (requires Python 3.11+)
	python3.13 -m venv .venv
	$(VENV_PY) -m pip install --upgrade pip --quiet
	.venv/bin/pip install -r requirements.txt --quiet

debug:  ## dbt debug — verify Snowflake connection
	$(DBT) debug

build:  ## dbt build — materialize all models, run all tests
	$(DBT) deps
	$(DBT) build

test:  ## Run only the tests (no rebuild)
	$(DBT) test

docs:  ## Generate dbt docs into target/
	$(DBT) docs generate

serve:  ## Serve dbt docs locally on http://localhost:8080
	$(DBT) docs serve

publish-docs:  ## Regenerate static site and stage into docs/index.html for GitHub Pages
	./scripts/build_docs.sh

ci-local:  ## Run the offline-only checks that CI runs (dbt parse with a stub profile)
	$(DBT) parse --no-partial-parse

clean:  ## Remove build artifacts and venv (keeps source files)
	rm -rf target/ dbt_packages/ logs/ .venv/
