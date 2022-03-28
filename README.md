# check-risk-label

![Latest Release](https://img.shields.io/github/v/release/zendesk/check-risk-label?label=Latest%20Release)
![Tests](https://github.com/zendesk/check-risk-label/workflows/Test/badge.svg?branch=main)

A custom Github Action for use on pull requests. The action:

 * ensures that the four labels "risk:none/low/medium/high" are correctly defined in the repository;
 * ensures that exactly one of those labels is applied to the PR;
 * ensures that some specific text (i.e. part of the PR template) is _not_ in the PR description.

All parts are optional. See 'Inputs'.

## Inputs

See `inputs` in [action.yml](https://github.com/zendesk/check-risk-label/blob/main/action.yml).

## Output

This Action has no outputs.

## Usage of the Github action

```yaml
---
name: Check risk
on:
  pull_request:
    types: [opened, edited, labeled, unlabeled]

jobs:
  check-risk:
    name: Check risk
    steps:
      - name: Check risk
        uses: zendesk/check-risk-label@VERSION
```

where VERSION is the version you wish you use, e.g. `v1` (or a branch, or a commit hash).
Check the top of this readme to find the latest release.
