# TS-01 — sshd crash → auto restart

## Given

- Target EC2 healthy; SSM online
- CloudWatch metric/alarm for sshd
- ServiceNow can create incidents from Lambda
- AWX job template `remediate_sshd` works manually

## When

Via SSM Run Command on target:

```bash
systemctl stop sshd
```

## Then

1. CloudWatch alarm → ALARM
2. ServiceNow incident with instance id in description
3. AWX job succeeds
4. `systemctl is-active sshd` → active
5. Incident work note + resolved

## Pass / fail

- **Pass:** SSH works again; ticket closed without manual Ansible click
- **Fail:** no ticket, job not triggered, or sshd still down
