# Opta Codebase Analysis

## General Overview
- Opta is positioned as a higher-level Infrastructure-as-Code framework on top of Terraform that ships curated modules for common cloud services across AWS, GCP, and Azure, while still allowing escape hatches for custom Terraform or direct Kubernetes manifests (`README.md:1`).  
- The repository blends a Python CLI (`opta/cli.py:1`), Terraform modules (`modules/**/tf_module`), and Helm charts (`modules/opta-k8s-service-helm`) to abstract multi-cloud provisioning and service deployment workflows.  
- Examples such as the Bring Your Own EKS cluster walk-through demonstrate how Opta-generated Terraform and Helm bundles can be used incrementally alongside existing infrastructure (`examples/byok-eks/README.md:1`).  
- Tooling is standardized with Black, isort, and pytest defaults codified in `pyproject.toml` to keep the Python layer consistent (`pyproject.toml:1`).

## Architecture and Key Components

### CLI and Command Surface
- The Click-based CLI (`opta/cli.py:1`) wires top-level commands (`apply`, `deploy`, `destroy`, `validate`, etc.) into a single entry-point with automatic clean-up and friendly error handling.  
- Operational commands like `apply` orchestrate Terraform generation, remote state coordination, Kubernetes connectivity checks, and telemetry/analytics emission before invoking Terraform workflows (`opta/commands/apply.py:1`).  
- Crash handling funnels through a central reporter so user errors are surfaced differently from internal exceptions (`opta/cli.py:65`).

### Layers, Modules, and Registry
- `Layer` objects encapsulate a stack’s providers, modules, and parent relationships, dynamically loading the right `ModuleProcessor` subclasses via the registry in `opta/layer.py:1`.  
- The registry maps module identifiers (e.g., `aws-k8s-base`, `k8s-manifest`) to Python processors, which mutate module data, enforce pre/post hooks, and manage dependencies before Terraform is rendered (`opta/layer.py:50`).  
- Module schemas live in YAML/JSON pairs (for docs and validation), with user-facing knobs such as `linkerd_enabled`, `linkerd_high_availability`, and ingress tuning surfaced in `modules/aws_k8s_base/aws-k8s-base.yaml:1`.  
- Generic modules like `k8s-manifest` give users a direct path to apply arbitrary Kubernetes YAML through Terraform’s `kubernetes_manifest` resource (`modules/k8s_manifest/tf_module/main.tf:1`).

### Infrastructure Modules and Terraform Bridge
- Each module’s `tf_module` directory contains Terraform that Opta stitches together. For example, the AWS Kubernetes base module orchestrates ingress, metrics, autoscaling, Linkerd, and supporting IAM assets (`modules/aws_k8s_base/tf_module`).  
- Terraform code is parameterized by processor-populated variables such as cluster names, certificates, DNS zones, and feature flags defined in `modules/aws_k8s_base/tf_module/variables.tf:1`.  
- Cloud-specific processors (e.g., `AwsK8sBaseProcessor`) enrich module data by wiring outputs from prerequisite modules (like EKS cluster names, DNS certificates) before rendering Terraform and running hooks to manage cluster state (`modules/aws_k8s_base/aws_k8s_base.py:1`).

### Helm-Based Kubernetes Services
- Opta-generated services use a shared Helm chart under `modules/opta-k8s-service-helm`, which injects operational defaults—Linkerd annotations, Datadog labels, readiness gate logic, and optional cronjobs—driven by module configuration.  
- Deployments automatically set Linkerd proxy resource requests, skip outbound ports for databases/UDP telemetry, and expose tap metrics annotations (`modules/opta-k8s-service-helm/templates/deployment.yaml:20`).  
- Namespace templates mark every Opta-created namespace for Linkerd injection, guaranteeing mesh coverage unless explicitly overridden (`modules/opta-k8s-service-helm/templates/namespace.yaml:1`).  
- Cron workloads intentionally disable Linkerd injection because of upstream Linkerd CronJob issues, showing how Opta encodes opinionated workarounds into its Helm assets (`modules/opta-k8s-service-helm/templates/crons.yaml:1`).

### Tooling, Examples, and Tests
- The repo ships curated examples (e.g., BYOK EKS) that illustrate the interplay between Terraform modules like ingress-nginx and Linkerd for operators who want to bootstrap only parts of Opta (`examples/byok-eks/README.md:20`).  
- Python and module-specific tests reside in `tests/` and `modules/tests/`, with fixtures validating behaviors such as Linkerd detection, port validation, and processor edge cases (`modules/tests/test_base.py:210`).  
- Formatting/testing defaults are codified in `pyproject.toml` and `setup.cfg`, while the Makefile and scripts directory provide contributor workflows for linting, packaging, and releases (`Makefile`).

## Linkerd on EKS Implementation

### Configuration Flags and Defaults
- Linkerd support is enabled by default in the AWS Kubernetes base module via the user-facing `linkerd_enabled`, `linkerd_high_availability`, and `linkerd_values` inputs, making mesh installation opt-out instead of opt-in (`modules/aws_k8s_base/aws-k8s-base.yaml:53`).  
- The corresponding Terraform variables define the toggleable booleans and map inputs consumed by the Linkerd Helm release (`modules/aws_k8s_base/tf_module/variables.tf:70`).  
- BYOK documentation reinforces that Linkerd is the supported mesh and explains how its Terraform module fits into bootstrap flows (`examples/byok-eks/README.md:20`).

### TLS Assets and Helm Release
- Opta generates Linkerd’s trust anchor and issuer certificates directly in Terraform using `tls_private_key`, `tls_self_signed_cert`, and `tls_locally_signed_cert` resources, avoiding manual certificate management (`modules/aws_k8s_base/tf_module/linkerd.tf:1`).  
- Sensitive values for `identityTrustAnchorsPEM`, issuer cert/key pairs, and expiry metadata are injected via `set_sensitive` blocks, ensuring the Helm release receives valid mTLS materials (`modules/aws_k8s_base/tf_module/linkerd.tf:60`).  
- High-availability mode concatenates a baked `values-ha.yaml` file—tuning replica counts, resource requests, and admission-webhook namespace selectors—with any user-provided overrides to harden the control plane across availability zones (`modules/aws_k8s_base/tf_module/values-ha.yaml:1`).  
- Default `podAnnotations` (safe-to-evict) are layered onto the chart values to play nicely with the cluster autoscaler even when HA mode is disabled (`modules/aws_k8s_base/tf_module/linkerd.tf:88`).

### Ingress-NGINX and Mesh Integration
- The ingress controller Helm release enforces Linkerd injection on controller pods, configures skip inbound ports for 80/443, enables Viz tap, and tunes proxy requests so the control plane can observe traffic at the cluster boundary (`modules/aws_k8s_base/tf_module/ingress_nginx.tf:60`).  
- Additional annotations configure the AWS NLB (scheme, protocol, TLS policy, ALPN, certificate selection) so that Linkerd can terminate mTLS internally while exposing HTTPS to the public via AWS load balancers (`modules/aws_k8s_base/tf_module/ingress_nginx.tf:116`).  
- DNS records (optional) point Route53 zones at the ingress NLB, closing the loop between Linkerd-secured in-cluster traffic and user-facing endpoints (`modules/aws_k8s_base/tf_module/ingress_nginx.tf:169`).

### Namespace and Workload Injection
- When Opta creates namespaces, it annotates them with `linkerd.io/inject=enabled`, guaranteeing that any workload deployed through Opta’s Helm chart automatically receives Linkerd sidecars (`opta/core/kubernetes.py:233`).  
- The shared Helm chart for services applies proxy resource hints, skip-outbound-ports lists for UDP/databases, Datadog autodiscovery annotations, and Viz tap flags to every deployment, ensuring consistent Linkerd telemetry across services (`modules/opta-k8s-service-helm/templates/deployment.yaml:20`).  
- CronJobs explicitly disable injection to work around upstream CronJob proxy restarts (`modules/opta-k8s-service-helm/templates/crons.yaml:31`), highlighting where the mesh is intentionally bypassed.  
- `K8sServiceModuleProcessor` enforces Linkerd presence when users target existing clusters (Helm/BYOK mode) by checking for control-plane namespaces labeled `linkerd.io/is-control-plane=true` before allowing new workloads to deploy (`modules/base.py:327`).

### Runtime Safeguards and Tests
- `_check_byok_ready` ensures BYOK users install both Linkerd and nginx-ingress before Opta touches the cluster, preventing partially managed states (`modules/base.py:327`).  
- Unit tests cover the namespace detection logic, verifying various label/phase combinations so Opta does not mis-detect Linkerd installations or proceed while the mesh is terminating (`modules/tests/test_base.py:242`).  
- Namespace detection relies on Kubernetes API calls that are already initialized via Opta’s kubeconfig helpers, so failures surface early during the `pre_hook` phase of module processing (`modules/base.py:320`).

### Operational Notes
- Opta propagates Linkerd-specific annotations to user pods, ingress, and namespaces, but still lets operators supply custom Helm values via `linkerd_values` to tweak timers, addons, or additional workloads (`modules/aws_k8s_base/tf_module/linkerd.tf:88`).  
- BYOK Terraform examples include a standalone `linkerd.tf` module for operators who want to install Linkerd manually yet remain compatible with Opta’s expectations, mirroring the built-in module’s chart source and HA defaults (`examples/byok-eks/terraform/linkerd.tf:2`).  
- Cron workloads running without the mesh and the explicit skip-port annotations for database traffic are documented in chart templates, clarifying which traffic bypasses Linkerd intentionally (`modules/opta-k8s-service-helm/templates/deployment.yaml:32`).  
- Because ingestion is annotation-driven, any namespace or workload Opta does not create will need manual `linkerd.io/inject` labels to benefit from the mesh—an important caveat for hybrid clusters mixing Opta and legacy workloads.

