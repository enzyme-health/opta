terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 1.13.3"
    }
  }
}

resource "helm_release" "k8s-service" {
  chart = "${path.module}/../../opta-k8s-service-helm"
  name  = "${var.layer_name}-${var.module_name}"
  values = [
    yamlencode({
      deployment_timestamp = timestamp()
      autoscaling = {
        minReplicas = var.min_containers
        maxReplicas = var.max_containers
        targetCPUUtilizationPercentage = var.autoscaling_target_cpu_percentage
        targetMemoryUtilizationPercentage = var.autoscaling_target_mem_percentage
      }
      httpPort = var.http_port
      probePort = var.probe_port
      ports = var.ports
      serviceAnnotations = var.service_annotations
      containerResourceRequests = {
        cpu = "${var.resource_request["cpu"]}m"
        memory = "${var.resource_request["memory"]}Mi"
      }
      deployPods = (local.uppercase_image != "AUTO") || (var.tag != null) || (var.digest != null)
      image = local.image
      version = var.tag == null ? "latest" : var.tag
      livenessProbePath = var.healthcheck_path == null || var.liveness_probe_path != null ? var.liveness_probe_path : var.healthcheck_path
      livenessProbeCommand = length(var.healthcheck_command) == 0 || length(var.liveness_probe_command) != 0 ? var.liveness_probe_command : var.healthcheck_command
      initialLivenessDelay = var.initial_liveness_delay
      readinessProbePath = var.healthcheck_path == null || var.readiness_probe_path != null ? var.readiness_probe_path : var.healthcheck_path
      readinessProbeCommand = length(var.healthcheck_command) == 0 || length(var.readiness_probe_command) != 0 ? var.readiness_probe_command : var.healthcheck_command
      initialReadinessDelay = var.initial_readiness_delay
      healthcheck_path = var.healthcheck_path
      envVars = var.env_vars
      linkSecrets = var.link_secrets
      uriComponents = local.uri_components
      layerName = var.layer_name
      moduleName = var.module_name
      environmentName = var.env_name
      iamRoleArn = aws_iam_role.k8s_service.arn
      stickySession = var.sticky_session
      stickySessionMaxAge = var.sticky_session_max_age
      consistentHash = var.consistent_hash
      keepPathPrefix = var.keep_path_prefix
      persistentStorage = var.persistent_storage
      ingressExtraAnnotations = var.ingress_extra_annotations
      tolerations = var.tolerations
      cron_jobs = var.cron_jobs
      podAnnotations = var.pod_annotations
      podLabels = var.pod_labels
      commands = var.commands
      args = var.args
    })
  ]
  atomic          = true
  cleanup_on_fail = true
  timeout         = var.timeout
  max_history     = var.max_history
}

