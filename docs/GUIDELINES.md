# Engineering Guidelines

## Testing

It's essential to ensure that the code is tested thoroughly and of high quality.
Techniques such as unit tests and integration tests are strictly enforced, and
it's highly encouraged to use property-based and formal verification methods.

> Tests should be written, not only to verify correctness of the target code,
> but to be comprehensively reviewed by other programmers. Therefore, for
> mission critical Solidity code, the quality of the tests are just as important
> (if not more so) than the code itself, and should be written with the highest
> standards of clarity and elegance.

Every addition or change to the code must come with relevant and comprehensive
tests.

Flaky tests are not acceptable.

The test suite should run automatically for every change in the repository, and
in pull requests tests must pass before merging.

The test suite coverage must be kept as close to 100% as possible, enforced in
pull requests.

## Code style

Solidity code should be written in a consistent format enforced by a linter,
following the official
[Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html).
See below for further [Solidity Conventions](#solidity-conventions).

We prioritize readability and understandability by keeping the code simple and
straightforward.Before writing any code, make sure you have a clear picture of
the system in your head. If you can't visualize it, it means you need to ask
more questions until you can see the entire system in your mind. Understanding
the downstream effects of any changes is vital. Only once you have this
comprehensive view should you begin writing code.

Consistency and predictability should be maintained across the codebase. In
particular, this applies to naming, which should be systematic, clear, and
concise.

Sometimes these guidelines may be broken if doing so brings significant
efficiency gains, but explanatory comments should be added.

Modularity should be pursued, but not at the cost of the above priorities.

## Documentation

For contributors, project guidelines and processes must be documented publicly.

For users, features must be abundantly documented. Documentation should include
answers to common questions, solutions to common problems, and recommendations
for critical decisions that the user may face.

## Peer review

All changes must be submitted through pull requests and go through peer code
review.

The review must be approached by the reviewer in a similar way as if it was an
audit of the code in question (but importantly it is not a substitute for).

Reviewers should enforce code and project guidelines.

External contributions must be reviewed separately by multiple maintainers.

## Governance

Moonwell uses
[Forge Proposal Simulator](https://github.com/solidity-labs-io/forge-proposal-simulator/)
to simplify governance proposals and ensure that any changes made to the
protocol are rigorously tested before implementation. Any updates to the
protocol must go through a governance proposal and can only be applied after
community approval. Refer to [Governance](./governance/README.md) for guidance
on how to create a proposal once you have a Pull Request ready.

## Pull requests

Pull requests are squash-merged to keep the `main` branch history clean. The
title of the pull request becomes the commit message, so it should be written in
a consistent format:

1. Begin with a capital letter.
2. Do not end with a period.
3. Write in the imperative: "Add feature X" and not "Adds feature X" or "Added
   feature X".

This repository does not follow conventional commits, so do not prefix the title
with "fix:" or "feat:".

Work in progress pull requests should be submitted as Drafts and should not be
prefixed with "WIP:".

Branches should be named in a consistent format:

1. Begin with a lowercase letter.
2. Use hyphens to separate words.
3. Use a short and descriptive name.

# Security Policy

Security vulnerabilities should be disclosed to the project maintainers through
[Immunefi](https://immunefi.com/bounty/moonwell/), or alternatively by email to
[TBD]()

# Solidity Conventions

In addition to the official Solidity Style Guide we have a number of other
conventions that must be followed.

- [CEI](https://fravoll.github.io/solidity-patterns/checks_effects_interactions.html)
  pattern should be followed for external calls.

- Interface names should have a capital I prefix.

  ```solidity
  interface IERC777 {
  ```

- Unchecked arithmetic blocks should contain comments explaining why overflow is
  guaranteed not to happen. If the reason is immediately apparent from the line
  above the unchecked block, the comment may be omitted.

- Revert messages should be clear and concise and include dynamic data where
  appropriate.
