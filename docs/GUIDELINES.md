# Engineering Guidelines

## Testing

Moonwell has a high bar for contributions to the codebase. Engineers are expected to have several layers of testing for
all Solidity code: unit, fuzz, integration, and invariant testing. Formal verification should be used if it is a good
fit for the problem.

All contributions should have 100% code coverage. All testing types should be used. Code must be tested in as close to
the real world conditions. You can see your coverage using the forge coverage command. Note: the accuracy of the
coverage tool is not authoritative; if you can show your lines of code were covered, that’s sufficient.

You may contribute to formal verification for your patch, however this is not a strict requirement. For complex changes
to the protocol, formal verification is recommended.

The test suite should run automatically for every change in the repository, and in pull requests tests must pass before
merging.

The test suite coverage must be kept as close to 100% as possible, enforced in pull requests.

## Code style

The most important principle in writing code is clarity. Code should be as obvious as possible. We always prefer clear
over clever. The following are a list of principles to follow to lead in the right direction for your patch.

1. Prefer local context. Try to not do too much in one function. Do not hide complexity by calling into complex
   sub-routines.
2. Variables should be clearly named, even if it makes the name long. You can use Hungarian-like notation for variables
   like supplyAmountMantissa, here indicating the value is a real number with 18 decimals of precision.
3. Your code should be clear without comments, and should have comments to make things crystal clear to other
   contributors what the intent behind each line of code is.
4. Prefer the order
   [Checks, Effects then Interactions](https://fravoll.github.io/solidity-patterns/checks_effects_interactions.html) and
   generally avoid cross-contract interactions where possible. Additionally, avoid interspersing computation with
   effects and interactions (e.g. if you can calculate a value upfront, do so).
5. Try to match the code-style that already exists in the repository. Please do not refactor existing code styles.
6. Public functions should have NatSpec documentation, including: a notice briefly describing the purpose, what the
   parameters are, and what the return value is.
7. Unchecked arithmetic blocks should contain comments explaining why under or over flows are guaranteed not to happen.
   If the reason is immediately apparent from the line above the unchecked block, the comment may be omitted.
8. Revert messages should be clear and concise and include dynamic data where appropriate.

## Documentation

For contributors, project guidelines and processes must be documented publicly.

For users, features must be abundantly documented. Documentation should include answers to common questions, solutions
to common problems, and recommendations for critical decisions that the user may face.

## Peer review

All changes must be submitted through pull requests and go through code review.

The review must be approached by the reviewer in a similar way as if it was an audit of the code in question (but
importantly it is not a substitute for). See [this checklist](https://github.com/solidity-labs-io/code-review-checklist)
for how to conduct a proper code review.

Reviewers should enforce code and project guidelines.

External contributions must be reviewed separately by multiple maintainers.

## Governance

Moonwell uses [Forge Proposal Simulator](https://github.com/solidity-labs-io/forge-proposal-simulator/) to simplify
governance proposals and ensure that any changes made to the protocol are rigorously tested before implementation and
easy to review. Any updates to the protocol must go through a governance proposal and can only be applied after
community approval. Refer to [Governance](./governance/CONTRIBUTING.md) for guidance on how to create a proposal once
you have a Pull Request ready.

## Pull requests

The title of the pull request becomes the commit message, so it should be written in a consistent format:

1. Begin with a capital letter.
2. Do not end with a period.
3. Write in the imperative: "Add feature X" and not "Adds feature X" or "Added feature X".

This repository does not follow conventional commits, so do not prefix the title with "fix:" or "feat:".

Work in progress pull requests should be submitted as Drafts and should not be prefixed with "WIP:".

Branches should be named in a consistent format:

1. Begin with a lowercase letter.
2. Use hyphens to separate words.
3. Use a short and descriptive name.

## Security Policy

Security vulnerabilities should be disclosed to the project maintainers through
[Immunefi](https://immunefi.com/bounty/moonwell/).
