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

VERSION := 3.2.0
MVN = $(MAVEN) --batch-mode --no-transfer-progress \
  -Dmaven.repo.local=$(MAVEN-REPOSITORY)

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
	$(PERL) util/maven-release check-version '$(v)'

release: release-check test $(MAVEN) $(PERL) $(YS)
	YS=$(YS) $(PERL) util/maven-release release \
	  $(MAVEN) $(MAVEN-REPOSITORY) -DskipTests

test-release: $(PERL) $(YS)
	YS=$(YS) $(PERL) test/maven-release.t
