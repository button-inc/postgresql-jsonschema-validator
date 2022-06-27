SHELL := /usr/bin/env bash
__FILENAME := $(lastword $(MAKEFILE_LIST))
__DIRNAME := $(abspath $(realpath $(lastword $(MAKEFILE_LIST)))/../)
PERL=perl
PERL_VERSION=${shell ${PERL} -e 'print substr($$^V, 1)'}
PERL_MIN_VERSION=5.10
PSQL=psql -h localhost -v "ON_ERROR_STOP=1"
CPAN=cpan
# CPANM home has to be in the current directory, so that it can find the
# pg_config executable, installed via asdf
CPANM=PERL_CPANM_HOME=$(__DIRNAME)/.cpanm cpanm --notest
DB_NAME=jsonschema
PG_PROVE=pg_prove -h localhost
PGTAP_VERSION=1.2.0

help: ## Show this help.
	@sed -ne '/@sed/!s/## //p' $(MAKEFILE_LIST)

.PHONY: install_asdf_tools
install_asdf_tools: ## install languages runtimes and tools specified in .tool-versions
install_asdf_tools:
	@cat .tool-versions | cut -f 1 -d ' ' | xargs -n 1 asdf plugin-add || true
	@asdf plugin-update --all
	@#MAKELEVEL=0 is required because of https://www.postgresql.org/message-id/1118.1538056039%40sss.pgh.pa.us
	@MAKELEVEL=0 POSTGRES_EXTRA_CONFIGURE_OPTIONS='--with-libxml' asdf install
	@asdf reshim
	@pip install -r requirements.txt
	@asdf reshim

.PHONY: install_pgtap
install_pgtap: ## install pgTAP extension into postgres
install_pgtap: start_pg
install_pgtap:
	@$(PSQL) -d postgres -tc "select count(*) from pg_available_extensions where name='pgtap' and default_version='$(PGTAP_VERSION)';" | \
		grep -q 1 || \
		(git clone https://github.com/theory/pgtap.git --depth 1 --branch v$(PGTAP_VERSION) && \
		$(MAKE) -C pgtap && \
		$(MAKE) -C pgtap install && \
		$(MAKE) -C pgtap installcheck && \
		rm -rf pgtap)

.PHONY: install_cpanm
install_cpanm: ## install the cpanm tool
install_cpanm:
ifeq ($(shell which $(word 2,$(CPANM))),)
	# install cpanm
	@$(CPAN) App::cpanminus
endif

.PHONY: install_cpandeps
install_cpandeps: ## install Perl dependencies from cpanfile
install_cpandeps:
	@$(CPANM) --installdeps .
	@rm -rf $(__DIRNAME)/.cpanm

.PHONY: install_perl_tools
install_perl_tools: ## install cpanm and sqitch
install_perl_tools: install_cpanm install_cpandeps

.PHONY: install_dev_tools
install_dev_tools: ## install development tools
install_dev_tools: stop_pg install_asdf_tools install_perl_tools install_pgtap

.PHONY: start_pg
start_pg: ## start the database server if it is not running
start_pg:
	@pg_ctl status || pg_ctl start

.PHONY: stop_pg
stop_pg: ## stop the database server. Always exits with 0
stop_pg:
	@pg_ctl stop; true

.PHONY: create_test_db
create_test_db: ## Ensure that the $(DB_NAME)_test database exists
create_test_db:
	@$(PSQL) -d postgres -tc "SELECT count(*) FROM pg_database WHERE datname = '$(DB_NAME)_test'" | \
		grep -q 1 || \
		$(PSQL) -d postgres -c "CREATE DATABASE $(DB_NAME)_test" &&\
		$(PSQL) -d $(DB_NAME)_test -c "create extension if not exists pgtap";


.PHONY: drop_test_db
drop_test_db: ## Drop the $(DB_NAME)_test database if it exists
drop_test_db:
	@$(PSQL) -d postgres -tc "SELECT count(*) FROM pg_database WHERE datname = '$(DB_NAME)_test'" | \
		grep -q 0 || \
		$(PSQL) -d postgres -c "DROP DATABASE $(DB_NAME)_test";

.PHONY: deploy_test_db_migrations
deploy_test_db_migrations: ## deploy the test database migrations with sqitch
deploy_test_db_migrations: start_pg create_test_db
deploy_test_db_migrations:
	$(PSQL) -d $(DB_NAME)_test -f $(__DIRNAME)/src/validate-json.sql


.PHONY: test
test: ## run the database unit tests
test: | start_pg drop_test_db create_test_db deploy_test_db_migrations
test:
	@$(PG_PROVE) -v -d $(DB_NAME)_test test/*.sql
