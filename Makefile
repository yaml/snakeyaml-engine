M ?= .cache/makes
MAKES-COMMIT := 0a4d1e3f63afe1cd36eacb0babec7bcfebdbe494
$(shell test -d $M || { \
  git clone -q https://github.com/makeplus/makes $M && \
  git -C $M checkout -q $(MAKES-COMMIT); \
})
include $M/init.mk
include $M/maven.mk
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

bundle: $(MAVEN)
	$(MVN) deploy -Prelease -DskipTests -Dcentral.skipUpload=true

release: test
	@test "$(CENTRAL_NAMESPACE_VERIFIED)" = org.yamlstar || { \
	  echo 'Verify org.yamlstar Central ownership, then set' >&2; \
	  echo 'CENTRAL_NAMESPACE_VERIFIED=org.yamlstar' >&2; exit 1; }
	$(MVN) deploy -Prelease -DskipTests
