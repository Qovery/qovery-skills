# Networking and domains

Covers custom domains and TLS certificates, request timeouts, the NGINX Ingress to Envoy Gateway (Gateway API) move, inbound and outbound IPs, IP allowlists, VPC peering, WAFs and service-to-service traffic. This is one of the largest support topics.

## Contents

- First: which router does the cluster use?
- 504 Gateway Timeout or `upstream request timeout`
- Custom domain has no certificate, or a certificate error
- Wildcard domains and a custom domain for the whole cluster
- Static outbound IP (allowlisting with a third party)
- Inbound IPs and restricting who can reach a service
- Large uploads, CORS, sticky sessions and other ingress behavior
- Private services and internal load balancers
- WAF in front of Qovery
- Blue/green, canary and moving a domain between services
- VPC peering and reaching resources in another VPC
- Service-to-service traffic and network policies
- Control-plane IPs to allow in a firewall
- Known limits

## First: which router does the cluster use?

Qovery clusters route HTTP traffic either through the NGINX Ingress controller (older setup) or through Envoy Gateway with the Kubernetes Gateway API (current setup). The service advanced settings come in two families and only the family matching the cluster's router has an effect:

- `network.ingress.*` applies to NGINX Ingress.
- `network.gateway_api.*` applies to Envoy Gateway.

Check the cluster advanced settings: `k8s.use_api_gateway` set to `true` means Gateway API is the default router for the cluster's services. A cluster can run both during a migration (`k8s.deploy_api_gateway`). Many "it worked before" reports after a migration come from settings still set on the NGINX family, or from a cluster where Gateway API was deployed but never made the default. Migration guide: <https://www.qovery.com/changelog/nginx-ingress-controller-migration>. Settings: <https://www.qovery.com/docs/configuration/cluster-advanced-settings>.

After changing a cluster advanced setting, the cluster must be redeployed, and usually the services too, for the generated routes to pick up the change.

## 504 Gateway Timeout or `upstream request timeout`

**Symptom.** Long requests (exports, reports, uploads, slow API calls) fail with `504` or `upstream request timeout`, often after about 15 seconds, typically after the move to Envoy Gateway.

**Likely cause.** With no timeout set, Envoy uses its default request timeout of 15 seconds, shorter than what the app needs.

**Fix.**
- For one service: set `network.gateway_api.http_request_timeout_seconds` in the service advanced settings (for example `120`), then redeploy the service.
- For every service on the cluster: set `envoy.gateway_api.http_request_timeout_seconds` in the cluster advanced settings, redeploy the cluster, then redeploy the services. The service value overrides the cluster value.
- On NGINX clusters the equivalent service settings are `network.ingress.proxy_read_timeout_seconds` and `network.ingress.proxy_send_timeout_seconds`.
- Long-lived connections (WebSockets, streaming) may also need `network.gateway_api.http_connection_idle_timeout_seconds` or `network.gateway_api.http_max_stream_duration_seconds`.

**Confirm.** Retry the slow request after the redeploy.

Docs: <https://www.qovery.com/docs/configuration/service-advanced-settings>, <https://www.qovery.com/docs/configuration/cluster-advanced-settings>.

## Custom domain has no certificate, or a certificate error

**Symptom.** The custom domain shows an error in the Console; the certificate stays pending; the browser shows `ERR_CERT_COMMON_NAME_INVALID` or a Qovery default certificate.

**Likely causes.**
- The CNAME is missing, points to the wrong target, or has not propagated yet when the certificate was requested. Let's Encrypt validates through DNS resolution, so the record must resolve first.
- The service was deleted and recreated: its Qovery-assigned domain changed, so the old CNAME points nowhere.
- The domain is behind Cloudflare in proxied mode while **Generate certificate** is on (or the opposite).
- A wildcard domain on a DNS zone that is not connected to the cluster: Qovery cannot issue a wildcard certificate there.
- After an NGINX to Envoy Gateway migration, the cluster still routes through NGINX, or the browser cached the old certificate.

**How to check.**
```bash
dig +short app.example.com CNAME     # must return the target shown in the service's Domains settings
```
Compare with the target displayed in the Console for that domain. One CNAME is needed per custom domain, even for several subdomains of the same root.

**Fix.**
1. Create or correct the CNAME to the exact target from the Console, wait for it to resolve, then redeploy the service.
2. Cloudflare in **DNS only** mode: keep **Generate certificate** on. Cloudflare **Proxied**: turn on **Domain behind a CDN** (this turns off certificate generation, Cloudflare terminates TLS) and use Cloudflare's **Full** SSL mode.
3. Wildcards on a zone that is not connected to the cluster: turn off certificate generation, turn on CDN proxy mode, and let the CDN terminate TLS.

**Escalate when** DNS resolves correctly, the service was redeployed, and the certificate is still pending after about 30 minutes.

Docs: <https://www.qovery.com/docs/configuration/application#custom-domains>, <https://www.qovery.com/docs/getting-started/guides/advanced-tutorials/cloudflare-custom-domain>.

## Wildcard domains and a custom domain for the whole cluster

**Question.** "Can all my services use my own domain with one wildcard certificate instead of a Qovery-assigned domain?"

**Answer.** Yes, with the cluster's **Custom Domain and Wildcard TLS** feature, which needs the DNS zone hosted on Cloudflare or AWS Route 53 and connected to the cluster. Warn the user before they enable it: it changes the default domain of every service on the cluster, so all services are redeployed and any CNAME pointing to the old Qovery domains must be updated. Plan it as a maintenance window. Docs: <https://www.qovery.com/docs/configuration/clusters#custom-domain-and-wildcard-tls>.

Uploading your own certificate files for a service is not a standard option. Use the wildcard feature or terminate TLS at a CDN.

## Static outbound IP (allowlisting with a third party)

**Question.** "A partner, a SaaS API or a database host needs a fixed IP to allow our traffic."

**Answer.**
- AWS: the cluster **Static IP** feature sends outbound traffic through NAT gateways with Elastic IPs. It deploys NAT gateways, Elastic IPs and private subnets. Find the addresses in the AWS console under **VPC > Elastic IP addresses**. It is on by default for new clusters.
- It is selected when the cluster is created. The Network tab of an existing AWS cluster shows whether it is enabled but it cannot be changed afterwards; enabling it means creating a new cluster and moving the environments.
- GCP: stable Cloud NAT IPs through the NAT gateway option. Scaleway: a static egress IP option exists and needs the corresponding IAM permissions. Check the provider page in the docs.
- Without Static IP, each worker node has its own public IP, and nodes change over time, so there is no stable address to allowlist.

Docs: <https://www.qovery.com/docs/configuration/integrations/kubernetes/eks/managed>, <https://www.qovery.com/docs/getting-started/useful-resources/faq>.

## Inbound IPs and restricting who can reach a service

- Inbound traffic arrives through the cluster's load balancer. Its addresses are those your domain resolves to (`dig +short <qovery-or-custom-domain>`); they usually stay the same for the load balancer's lifetime but are not guaranteed if it is re-created. On AWS and Scaleway, Gateway API clusters can pin them with the cluster setting `k8s.gateway.load_balancer_ip_allocation_ids` (on AWS, one Elastic IP allocation ID per subnet or zone of the NLB; changing it re-creates the load balancer, so plan a short maintenance window).
- To allow only some source IPs on a service, set `network.gateway_api.whitelist_source_range` (Envoy) or `network.ingress.whitelist_source_range` (NGINX), comma-separated CIDRs. `...denylist_source_range` does the opposite. For basic authentication, `...basic_auth_env_var`.
- Behind Cloudflare, allow Cloudflare's IP ranges only, or use a Cloudflare Tunnel.

## Large uploads, CORS, sticky sessions and other ingress behavior

These are service advanced settings, in the family matching the cluster's router. Examples (check exact names in the docs page before recommending one):

| Need | Envoy Gateway | NGINX Ingress |
|---|---|---|
| CORS | `network.gateway_api.enable_cors`, `...cors_allow_origin` | `network.ingress.enable_cors`, `...cors_allow_origin` |
| Sticky sessions | `network.gateway_api.enable_sticky_session` | `network.ingress.enable_sticky_session` |
| Force HTTPS | `network.gateway_api.force_ssl_redirect` | `network.ingress.force_ssl_redirect` |
| Extra response headers | `network.gateway_api.add_headers` | `network.ingress.add_headers` |
| Rate limiting | `network.gateway_api.route_limit_rps` / `..._rpm` | `network.ingress.nginx_limit_rps` / `..._rpm` |
| Request body size | (no equivalent listed) | `network.ingress.proxy_body_size_mb` |

Docs: <https://www.qovery.com/docs/configuration/service-advanced-settings>.

## Private services and internal load balancers

- A service that only other services call does not need a public port. Remove its public exposure and call it through its internal host (see below).
- `aws.eks.alb_controller.load_balancer_scheme` (`internet-facing` or `internal`) is a **cluster-wide** setting: switching to `internal` makes every service on the cluster reachable only from the VPC, and replacing the load balancer causes a few minutes of downtime.
- There is no per-service internal load balancer. Workarounds: keep the service private and reach it through VPC peering or a VPN to the VPC, or expose a dedicated internal load balancer you manage.

## WAF in front of Qovery

There is no built-in WAF. On AWS, the cluster's traffic enters through a Network Load Balancer, and AWS WAF cannot be attached to an NLB. Put a WAF-capable layer in front: Cloudflare in proxied mode, or Amazon CloudFront with AWS WAF. Then restrict the service to the WAF's source ranges with the allowlist settings above, so nobody bypasses it.

## Blue/green, canary and moving a domain between services

- A custom domain belongs to one service at a time, and there is no weighted traffic split between two services.
- For a safe release, deploy the new version into the same service: the default rolling update replaces pods only once new ones are ready. Docs: <https://www.qovery.com/docs/configuration/deployment/strategies>.
- Moving a custom domain to another service issues a new certificate for it, so expect a short window of TLS errors. Do it in a quiet period.

## VPC peering and reaching resources in another VPC

**Question.** "My database or service lives in another VPC; how do my Qovery services reach it?"

**Answer.** VPC peering between the cluster VPC and the other VPC. The user creates and accepts the peering, updates the route table of their existing VPC, updates the Qovery VPC route table from the cluster's **Network** tab, and opens the security groups. Docs: <https://www.qovery.com/docs/configuration/integrations/aws/vpc-peering>.

Under Qovery's shared responsibility model, the peering and the user's own VPC are the user's responsibility. Route table changes made in the AWS console on the Qovery VPC, outside the Network tab, can be reverted the next time the cluster is deployed: always add Qovery-side routes through the Network tab.

## Service-to-service traffic and network policies

- Inside an environment, services reach each other through internal hostnames. Use the built-in variables Qovery injects (names ending in `_HOST_INTERNAL`) or an alias to them, rather than hard-coding hostnames. See `reference/secrets-env.md`.
- Built-in variables do not cross environments. To call a service in another environment, use its full Kubernetes DNS name (`<service-host>.<namespace>.svc.cluster.local`) as a plain value, and update it if that environment is recreated.
- Standard Kubernetes `NetworkPolicy` objects work. Qovery documents a pattern to isolate environments: <https://www.qovery.com/docs/getting-started/guides/advanced-tutorials/isolate-environments-network-policies>. Test on staging first.

## Control-plane IPs to allow in a firewall

The IPs Qovery's control plane uses (for example to reach a Kubernetes API or a Git server you restrict by IP) are published at `https://api.qovery.com/ips` (JSON).

## Known limits

- No per-service internal load balancer; the load balancer scheme is cluster-wide.
- No weighted traffic split; one custom domain per service.
- No built-in WAF.
- Static outbound IP cannot be turned on for an existing AWS cluster.
- Router-specific settings: a `network.ingress.*` setting has no effect on a service routed by Envoy Gateway, and the reverse.
