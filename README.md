# sshd auto-remediation lab

AWS EC2 `sshd` down → CloudWatch alarm → ServiceNow incident → Ansible (AWX/AAP) restarts `sshd` via SSM.

**GitHub:** https://github.com/tirupaalepu/sshd-auto-remediatio

## Lab topology

| Host | Role |
|------|------|
| EC2 target | App host; CloudWatch watches sshd |
| AWX/control | Job template `remediate_sshd` |
| ServiceNow PDI | Incident + outbound call to AWX |
| OpenSearch (optional) | Alert / job event index + RAG |

## Layout

```
terraform/     # VPC-free simple EC2 + IAM + CloudWatch + SNS
ansible/       # Playbooks (SSM restart sshd)
lambda/        # Alarm → ServiceNow incident
mcp/           # Optional Cursor MCP tools
docs/          # Runbooks + test scenario
```

## Prerequisites

- AWS CLI configured (`cursor-lab`, region `us-east-1`)
- GitHub remote: `origin` → this repo
- ServiceNow PDI credentials (later)
- AWX or AAP (later)

## Quick test (TS-01)

1. Stop sshd on target via SSM: `systemctl stop sshd`
2. Alarm → ServiceNow incident created
3. AWX job restarts sshd via SSM
4. Ticket updated / resolved

## Safety

Lab only. Prefer SSM over SSH for remediation (sshd may already be down). Stop EC2 when idle.
