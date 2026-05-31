.PHONY: setup up upgrade down reset dev e2e submodules lint port-forward seed build-all

# Auto-detect Colima's Docker socket so k3d and kubectl work on macOS without extra env setup
COLIMA_SOCK := $(HOME)/.colima/default/docker.sock
ifneq ($(wildcard $(COLIMA_SOCK)),)
  export DOCKER_HOST := unix://$(COLIMA_SOCK)
endif

# Empty Docker config dir so Helm skips docker-credential-osxkeychain
HELM := DOCKER_CONFIG=$(CURDIR)/.helm-docker-config helm

# Include locally built image overrides when the file exists (populated by make build-all)
LOCAL_IMAGES_VALUES := $(wildcard values/local-images.yaml)
HELM_LOCAL_IMAGES := $(if $(LOCAL_IMAGES_VALUES),-f values/local-images.yaml,)

UNAME := $(shell uname)

setup:
ifeq ($(UNAME), Darwin)
	bash scripts/setup-colima.sh
else
	bash scripts/setup-k3s.sh
endif

submodules:
	git submodule update --init --recursive

up:
	mkdir -p .helm-docker-config
	$(HELM) dependency update
	bash scripts/stub-disabled-charts.sh
	$(HELM) install greenstand . -f values/local.yaml $(HELM_LOCAL_IMAGES)

upgrade:
	mkdir -p .helm-docker-config
	$(HELM) dependency update
	bash scripts/stub-disabled-charts.sh
	$(HELM) upgrade greenstand . -f values/local.yaml $(HELM_LOCAL_IMAGES)

build-all:
	bash scripts/build-all.sh

down:
	$(HELM) uninstall greenstand

reset:
	k3d cluster delete greenstand 2>/dev/null || true
	k3d registry delete greenstand-registry 2>/dev/null || true
	$(MAKE) setup

dev:
	@if [ -z "$(SERVICE)" ]; then echo "Usage: make dev SERVICE=<service-name>"; exit 1; fi
	skaffold dev --profile=$(SERVICE)

e2e:
	bash scripts/e2e.sh

lint:
	mkdir -p .helm-docker-config
	$(HELM) lint . -f values/local.yaml
	$(HELM) template greenstand . -f values/local.yaml > /dev/null

port-forward:
	kubectl port-forward svc/greenstand-postgres 5432:5432 &
	kubectl port-forward svc/greenstand-localstack 4566:4566 &

seed: port-forward
	sleep 3
	bash scripts/seed-localstack.sh
