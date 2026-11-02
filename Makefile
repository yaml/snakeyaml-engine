M ?= .cache/makes
MAKES-COMMIT := 0a4d1e3f63afe1cd36eacb0babec7bcfebdbe494
$(shell test -d $M || { \
  git clone -q https://github.com/makeplus/makes $M && \
  git -C $M checkout -q $(MAKES-COMMIT); \
})
include $M/init.mk
include $M/maven.mk
include $M/perl.mk
include $M/yamlscript.mk
include $M/shell.mk
include $M/clean.mk

VERSION := 3.2.1
MVN = $(MAVEN) --batch-mode --no-transfer-progress \
  -Dmaven.repo.local=$(MAVEN-REPOSITORY)

MAKES-CLEAN := target

default:: build

build: $(MAVEN)
	$(MVN) package -DskipTests

test: $(MAVEN)
	$(MVN) test

install: $(MAVEN)
	$(MVN) install -DskipTests

bundle: $(MAVEN) $(PERL) $(YS)
	YS=$(YS) $(PERL) util/maven-release bundle \
	  $(MAVEN) $(MAVEN-REPOSITORY) -DskipTests

release-check: $(PERL)
	ENGINE_RELEASE_ALLOW_BRANCH='$(a)' \
	  $(PERL) util/maven-release check-release '$(v)'

release: release-check
ifeq ($(d),1)
	ENGINE_RELEASE_ALLOW_BRANCH='$(a)' ENGINE_RELEASE_DRYRUN=1 \
	  $(PERL) util/maven-release workflow '$(v)'
else
	+$(MAKE) release-run v='$(v)' a='$(a)'
endif

release-run: $(MAVEN) $(PERL) $(YS)
	ENGINE_RELEASE_ALLOW_BRANCH='$(a)' YS=$(YS) \
	  $(PERL) util/maven-release workflow '$(v)' \
	  $(MAVEN) $(MAVEN-REPOSITORY) -DskipTests

release-upload: $(PERL)
	$(PERL) util/maven-release check-upload '$(v)'
	+$(MAKE) release-upload-run v='$(v)'

release-upload-run: $(MAVEN) $(PERL) $(YS)
	YS=$(YS) $(PERL) util/maven-release upload '$(v)' \
	  $(MAVEN) $(MAVEN-REPOSITORY) -DskipTests

test-release: $(PERL) $(YS)
	YS=$(YS) $(PERL) test/maven-release.t
	$(PERL) test/release-workflow.t
