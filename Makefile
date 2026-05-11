.PHONY: setup up upgrade down dev e2e submodules lint port-forward seed

# Empty Docker config dir so Helm skips docker-credential-osxkeychain (Podman setup)
HELM := DOCKER_CONFIG=$(CURDIR)/.helm-docker-config helm

setup:
	bash scripts/setup-k3s.sh

submodules:
	git submodule update --init --recursive

up:
	mkdir -p .helm-docker-config
	$(HELM) dependency update
	$(HELM) install greenstand . -f values/local.yaml

upgrade:
	mkdir -p .helm-docker-config
	$(HELM) dependency update
	$(HELM) upgrade greenstand . -f values/local.yaml

down:
	$(HELM) uninstall greenstand

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
