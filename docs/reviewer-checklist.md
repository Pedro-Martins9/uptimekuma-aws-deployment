# Reviewer checklist

Use this checklist when evaluating the repository. It distinguishes source-level checks, historical evidence, and live operational verification.

## Repository and documentation

- [x] Public repository with a root README.
- [x] Architecture and major AWS components documented.
- [x] Terraform roots and deployment prerequisites documented.
- [x] Recovery evidence and its measurement limitations documented.
- [x] Apache-2.0 license present.
- [x] Local Terraform state, plans, tfvars and key material excluded from Git.

## Automated checks

- [x] Full-history Gitleaks workflow passed on 24 November 2026 (run 238).
- [x] Previous Terraform format/validation workflow passed on the Terraform code revision (historical run linked in README).
- [ ] Re-run Terraform formatting and validation on the latest source if Terraform files or workflow logic change.
- [ ] Review GitHub Actions environment protection, repository variables/secrets and AWS OIDC trust policies in GitHub/AWS settings; these settings are not inspectable from the source tree alone.

## Operational evidence

- [x] Historical deployment run recorded successful application deployment.
- [x] Historical alert wiring and backup-freshness metric fix are linked from README.
- [x] EC2 replacement restore drill is documented.
- [ ] Perform a fresh endpoint check before claiming the dashboard is currently online.
- [ ] For a formal RPO/RTO claim, capture backup object/version identifiers, checksum output, SQLite integrity output, termination/request time and first healthy target time in the same drill.
- [ ] Publish a cost figure only with a dated Cost Explorer or billing export.

## Review guidance

The project is a portfolio implementation, not a continuously hosted production service. The strongest evidence is the demonstrated recovery after EC2 replacement, supported by infrastructure-as-code, federated deployment and operational controls. Do not interpret historical workflow runs as proof of current AWS runtime state.
