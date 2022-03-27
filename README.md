# check-risk-label

![Latest Release](https://img.shields.io/github/v/release/zendesk/check-risk-label?label=Latest%20Release)
![Tests](https://github.com/zendesk/check-risk-label/workflows/Test/badge.svg?branch=main)

A custom Github Action for use on pull requests. The action:

 * ensures that the four labels "risk:none/low/medium/high" are correctly defined in the repository;
 * ensures that exactly one of those labels is applied to the PR.

## Inputs

This Action has no inputs.

## Output

This Action has no outputs.

## Usage of the Github action

```yaml
---
name: Check risk
on:
  pull_request:
    types: [opened, labeled, unlabeled]

jobs:
  check-risk-label:
    name: Check for risk label
    steps:
      - name: Check risk label
        uses: zendesk/check-risk-label@VERSION
```

where VERSION is the version you wish you use, e.g. `v1`. Check the top of this readme
to find the latest release.
