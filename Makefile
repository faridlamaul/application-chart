UNITTEST_IMAGE=helmunittest/helm-unittest:4.3.0-1.2.1@sha256:28ea86c3e0b07f501f0c2e9c08b9f41e240f4a4b571cb5106b36cf0f0607e989

.PHONY: all lint test demo

all: lint test

# Lint the defaults and every example, then render the API example.
lint:
	helm lint . --strict
	for f in examples/*.yaml; do helm lint . --strict -f "$$f" || exit 1; done
	helm template app . -f examples/values-api.yaml > /dev/null

# Run the helm-unittest suites in tests/ (needs Docker).
test:
	docker run --rm --user "$$(id -u):$$(id -g)" -e HOME=/tmp -v "$$PWD:/apps" $(UNITTEST_IMAGE) .

# Re-record docs/assets/demo.gif, render.png and schema-guard.png (needs https://github.com/charmbracelet/vhs).
demo:
	vhs docs/demo/demo.tape
