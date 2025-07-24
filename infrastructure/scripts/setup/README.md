# 📈 Unicorn Store Monitoring Stack

This setup provisions a complete observability solution for the **Unicorn Store** application running on Amazon EKS:

- ✅ **Prometheus** (scraping JVM metrics via OpenTelemetry)
- ✅ **Grafana** (with dashboards, alert rules, contact point, and notification policy)
- ✅ **AWS Lambda integration** (webhook triggered alerts for JVM thread dump generation)

---

## 🔧 Components

| Component     | Description                                                                 |
|---------------|-----------------------------------------------------------------------------|
| **Prometheus**| Scrapes metrics from OTEL Collector, exposed via internal LoadBalancer      |
| **Grafana**   | Public LoadBalancer, preconfigured with datasources, dashboards, and alerts |
| **OTEL Collector** | Exposes metrics from Spring Boot actuator `/actuator/prometheus`    |
| **AWS Lambda**| Triggered via webhook when JVM thread threshold is exceeded                 |
| **ConfigMaps**| Provisioned via Helm sidecars for dashboard, datasource, alerts, etc.       |
| **Security Group**| Ingress on port 9090 for Prometheus ILB, limited to the VPC CIDR        |

---

## 🚀 Automated Setup Workflow

Executed by `monitoring.sh`:

1. 🔐 Generates a random Grafana admin password and stores it as a Kubernetes Secret
2. 📦 Installs **Prometheus** and **Grafana** via Helm with dynamic `values.yaml`
3. 📊 Downloads a JVM dashboard from Grafana.com (ID: `22108`)
4. 📡 Waits for the Grafana LoadBalancer to become available
5. 🔍 Searches the dashboard for panels using `jvm_threads_live_threads`
6. ⚠️ Creates an alert rule `High JVM Threads` with a configurable threshold
7. 🛰️ Creates a **Contact Point** named `lambda-webhook` (if not already present)
8. 📬 Creates a **Notification Policy** targeting the Lambda webhook
9. 🔐 Updates the **Security Group** of the Prometheus ILB to allow VPC ingress on port 9090
10. 🧪 Sends a test alert to the Lambda function to verify integration

---

## 📝 Output

After successful execution, you'll see:

- 🌍 **Grafana URL** (public ELB)
- 👤 **Username**: `admin`
- 🔑 **Password**: Randomly generated (saved in `grafana-credentials.txt`)
- ⚠️ Confirmation of alert rule and Lambda webhook setup
- ✅ Manual test payload sent to the Lambda endpoint

---

## 📁 File Structure

```bash
scripts/
├── monitoring.sh                  # Main setup script (self-contained)
├── grafana-credentials.txt       # Generated credentials for Grafana access
├── prometheus-values.yaml        # Generated Prometheus Helm values
├── grafana-values.yaml           # Generated Grafana Helm values
├── grafana-datasource.yaml       # Prometheus datasource config (ConfigMap)
├── jvm-dashboard.json            # Downloaded JVM dashboard
├── dashboard-provisioning.yaml   # Dashboard provisioning provider
├── grafana-alert-rules.yaml      # Alert rule group for live thread alert
├── lambda-alert-rule.json        # JSON for API-based alert rule provisioning
```

---

## 🛡️ Prerequisites

- Kubernetes cluster (Amazon EKS)
- IAM permissions for:
  - Lambda: `GetFunctionUrlConfig`, `CreateFunctionUrlConfig`, `AddPermission`
  - EC2: `DescribeLoadBalancers`, `AuthorizeSecurityGroupIngress`
- Installed tools: `kubectl`, `helm`, `aws`, `jq`, `curl`, `openssl`, `dig`

---

## ✅ Monitoring Coverage

- JVM Live Threads via `/actuator/prometheus`
- Alerts on high thread count (> 200 threads by default)
- Automatic Lambda invocation on threshold breach

---

## 📬 Example Lambda Payload

```json
{
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "alertname": "High JVM Threads",
        "severity": "critical",
        "cluster_type": "eks",
        "cluster": "unicorn-store",
        "task_pod_id": "example-pod",
        "container_name": "unicorn-store-spring",
        "namespace": "unicorn-store-spring"
      },
      "annotations": {
        "summary": "Test Alert",
        "description": "This is a test alert from Grafana setup script"
      }
    }
  ]
}
```

---

## 📎 Notes

- The script is **idempotent**: it safely replaces existing config
- All resources (dashboards, alerts, contacts, policies) are **provisioned via API or ConfigMaps**
- This setup is ideal for production observability of Spring Boot JVM apps on EKS