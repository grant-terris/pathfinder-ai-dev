# Pathfinder AI Dev — build and validation entry points.
#
#   make tools      download pinned CLI tools into .bin/
#   make validate   build every Kustomize overlay and validate the output
#   make test       run repo self-tests (currently: the portability guard)
#   make clean      remove build output

SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := validate

BIN   := $(CURDIR)/.bin
BUILD := $(CURDIR)/.build

KUBECONFORM_VERSION := v0.8.0
KUBECONFORM         := $(BIN)/kubeconform-$(KUBECONFORM_VERSION)

# Kubernetes version the manifests are validated against.
KUBE_VERSION ?= 1.35.0

# Every overlay Flux or a developer applies. Each must build and validate.
OVERLAYS := aks/addons aks/platform kind/addons kind/platform

# CRD schemas (Gateway API, agent-sandbox, CNPG, Flux) come from the community catalog,
# once those kinds appear (M3 onward).
CRD_SCHEMAS := https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json

OS   := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH := $(shell uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')

.PHONY: tools validate portability test clean

tools: $(KUBECONFORM)

$(KUBECONFORM):
	@mkdir -p $(BIN) $(BIN)/tmp
	@echo "Downloading kubeconform $(KUBECONFORM_VERSION) ($(OS)-$(ARCH))"
	@cd $(BIN)/tmp && \
	  curl -sSfLO https://github.com/yannh/kubeconform/releases/download/$(KUBECONFORM_VERSION)/kubeconform-$(OS)-$(ARCH).tar.gz && \
	  curl -sSfLO https://github.com/yannh/kubeconform/releases/download/$(KUBECONFORM_VERSION)/CHECKSUMS && \
	  grep " kubeconform-$(OS)-$(ARCH).tar.gz$$" CHECKSUMS | sha256sum -c - && \
	  tar -xzf kubeconform-$(OS)-$(ARCH).tar.gz kubeconform && \
	  mv kubeconform $(KUBECONFORM)
	@rm -rf $(BIN)/tmp

portability:
	@hack/check-base-portability.sh deploy/base

validate: portability $(KUBECONFORM)
	@mkdir -p $(BUILD)
	@for o in $(OVERLAYS); do \
	  out="$(BUILD)/$${o//\//-}.yaml"; \
	  kubectl kustomize "deploy/overlays/$$o" > "$$out"; \
	  if grep -q 'placeholder.pathfinder.dev' "$$out"; then \
	    echo "validate: FAILED: overlay $$o still contains a placeholder value from base" >&2; exit 1; \
	  fi; \
	  printf '%-16s ' "$$o"; \
	  $(KUBECONFORM) -strict -summary -kubernetes-version $(KUBE_VERSION) \
	    -schema-location default -schema-location '$(CRD_SCHEMAS)' "$$out"; \
	done

test:
	@hack/test-check-base-portability.sh

clean:
	rm -rf $(BUILD)
