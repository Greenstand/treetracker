.PHONY: setup up upgrade down dev e2e submodules lint port-forward seed

setup:
	bash scripts/setup-k3s.sh

submodules:
	git submodule update --init --recursive

up:
	helm dependency update
	helm install greenstand . -f values/local.yaml

upgrade:
	helm dependency update
	helm upgrade greenstand . -f values/local.yaml

down:
	helm uninstall greenstand

dev:
	@if [ -z "$(SERVICE)" ]; then echo "Usage: make dev SERVICE=<service-name>"; exit 1; fi
	skaffold dev --profile=$(SERVICE)

e2e:
	bash scripts/e2e.sh

lint:
	helm lint . -f values/local.yaml
	helm template greenstand . -f values/local.yaml > /dev/null

port-forward:
	kubectl port-forward svc/greenstand-postgres 5432:5432 &
	kubectl port-forward svc/greenstand-localstack 4566:4566 &

seed: port-forward
	sleep 3
	bash scripts/seed-localstack.sh
